/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file CoreSession.vala
 *
 * @brief Builds and owns the functional services of Tuner; no toolkit.
 */

using Gee;
using Tuner.Controllers;
using Tuner.Coordinators;
using Tuner.Events;
using Tuner.Models;
using Tuner.Providers;
using Tuner.Services;

namespace Tuner
{
    /**
     * @class CoreSession
     * @brief The functional half of the application.
     *
     * Creates the event bus, network state, settings, radio-browser provider, stores, controllers and
     * coordinators, wires them together, and follows the network. A presentation layer creates one,
     * passes itself in as the `Host`, and then uses the services through it. It can be created without
     * a toolkit being initialized.
     *
     * It is the `AppContext` that controllers and coordinators are given.
     */
    public class CoreSession : Object, AppContext
    {
        // ----------------------------------------------------------
        // Services
        // ----------------------------------------------------------

        public AppEventBus events { get { return _events; } }
        public StationSession session { get { return _session; } }
        public History history { get { return _history; } }
        public PlayerController player { get { return _player; } }
        public JukeboxController jukebox { get { return _jukebox; } }
        public ConnectionCoordinator connection { get { return _connection; } }

        /** @brief Application settings */
        public Settings settings { get; private set; }

        /** @brief Station directory (browse and search) */
        public DirectoryController directory { get; private set; }

        /** @brief Tape counter controller */
        public TapeCounterController tape_counter { get; private set; }

        /** @brief Starred stations and saved searches */
        public StarStore stars { get; private set; }

        /** @brief Hearted tracks kept for All Time across sessions */
        public HeartedArchive all_time { get; private set; }

        /** @brief Station directory provider */
        public DataProvider.API provider { get; private set; }

        /** @brief The state of the network, and the Cancellable that ends online work when it goes */
        public NetworkState network { get; private set; }

        /** @brief Cancellable for online processes (cancelled while offline) */
        public Cancellable offline_cancel { get { return network.cancellable; } }

        public string? cache_dir { get { return _cache_dir; } }

        /** @brief Per-user data folder, or null if it could not be created */
        public string? data_dir { get; private set; }

        public bool is_offline { get { return network.is_offline; } }
        public bool is_online { get { return network.is_online; } }


        // ----------------------------------------------------------
        // Privates
        // ----------------------------------------------------------

        private static NetworkMonitor NETMON = NetworkMonitor.get_default ();

        private Host _host;
        private string _app_id;
        private AppEventBus _events;
        private StationSession _session;
        private History _history;
        private PlayerController _player;
        private JukeboxController _jukebox;
        private ConnectionCoordinator _connection;
        private PlaybackRecoveryCoordinator _playback_recovery_coordinator;
        private UsageTrackingCoordinator _usage_tracking_coordinator;
        private HistoryRecorder _history_recorder;
        private string? _cache_dir;
        private uint _monitor_changed_id = 0;
        private bool _has_started = false;
        private bool _services_started = false;
        private bool _started = false;
        private ulong _directory_handler_id = 0;
        private StartupCoordinator? _startup_coordinator = null;
        private static bool _log_filter_installed = false;


        /**
         * @param host The presentation layer
         * @param app_id Application id; names the per-user cache and data folders
         */
        public CoreSession (Host host, string app_id)
        {
            Object ();
            _host   = host;
            _app_id = app_id;

            install_log_filter ();

            _cache_dir = stat_dir (Environment.get_user_cache_dir ());
            Paths.cache_dir = _cache_dir;
            data_dir = stat_dir (Environment.get_user_data_dir ());

            var starred_file = setup_runtime_storage ();

            _events = new AppEventBus ();
            network = create_network_state ();
            initialize_connectivity_monitoring ();

            settings = new Settings ();
            var radio = new RadioBrowser (null, network);
            provider = radio;
            _session = new StationSession ();
            _player = new PlayerController (events, settings, session, network);
            stars = new StarStore (starred_file, events, provider);
            radio.stars = stars;
            directory = new DirectoryController (provider, stars, network);
            _history = new History ();
            all_time = new HeartedArchive (settings, history);
            _jukebox = new JukeboxController (this, directory);
            tape_counter = new TapeCounterController (events, history, session);

            _connection = new ConnectionCoordinator (this, events, provider);
            _playback_recovery_coordinator = new PlaybackRecoveryCoordinator (this, events, player, settings);
            _usage_tracking_coordinator = new UsageTrackingCoordinator (settings, events, provider, session);
            _history_recorder = new HistoryRecorder (events, history, player);
        } // CoreSession


        // ----------------------------------------------------------
        // Starting
        // ----------------------------------------------------------

        /**
         * @brief Starts the services that should be up as early as possible: the directory connection and MPRIS.
         *
         * Safe to call more than once. A presentation layer may call this first, while it builds its window, so
         * that choosing a directory server overlaps the window being built, and `start()` later.
         */
        public void start_services ()
        {
            if (_services_started)
                return;
            _services_started = true;

            connection.start ();            // Starts choosing a server
            Services.DBus.initialize (this);
        } // start_services


        /**
         * @brief Starts everything that happens once per launch. Call once, when the window exists.
         *
         * Starts the services if they are not started yet, loads the starred stations and saved searches as
         * soon as the connection is ready, and runs the start-up flows: the start-up sound (if the host has
         * one), starting on the starred stations, and auto-play of the last station.
         */
        public void start ()
        {
            if (_started)
                return;
            _started = true;

            start_services ();

            _directory_handler_id = events.connection_state_changed_sig.connect ((state) => { load_directory_when_ready (); });
            load_directory_when_ready ();

            _startup_coordinator = new StartupCoordinator (this, events, settings, directory, _host.startup_sound_uri ());
            _startup_coordinator.start ();
        } // start


        /**
         * @brief Loads the starred stations and saved searches once, the first time the connection is ready.
         */
        private void load_directory_when_ready ()
        {
            if (connection.state != Events.ConnectionState.READY)
                return;

            if (_directory_handler_id != 0)
            {
                events.disconnect (_directory_handler_id);
                _directory_handler_id = 0;
            }
            directory.load ();
        } // load_directory_when_ready


        /**
         * @brief Hides the JSON-GLib warning about GDateTime, which the station files trigger and which means nothing.
         */
        private static void install_log_filter ()
        {
            if (_log_filter_installed)
                return;
            _log_filter_installed = true;

            Log.set_handler ("Json", LogLevelFlags.LEVEL_WARNING, (log_domain, log_level, message) =>
            {
                if (message != null && message.contains ("Boxed type 'GDateTime' is not handled by JSON-GLib"))
                    return;

                Log.default_handler (log_domain, log_level, message);
            });
        } // install_log_filter


        // ----------------------------------------------------------
        // AppContext: requests that go to the presentation layer
        // ----------------------------------------------------------

        /**
         * @brief Plays a station known only by its UUID, such as one in the All Time list.
         *
         * @param station_uuid The station's UUID
         * @return True if the station was found and accepted by the player (see PlayerController.request_station)
         */
        public async bool play_station_by_uuid_async (string station_uuid)
        {
            var uuids = new Gee.ArrayList<string> ();
            uuids.add (station_uuid);

            foreach (var station in yield directory.get_stations_by_uuid_async (uuids))
                return player.request_station (station);

            warning ("The station %s was not found, so it cannot be played", station_uuid);
            return false;
        } // play_station_by_uuid_async


        public void play_station_in_ui (Station station) { _host.play_station_in_ui (station); }

        public void present_window () { _host.present_window (); }

        public void choose_starred_stations () { _host.choose_starred_stations (); }

        public bool render_icon (string resource, int size_px, string png_path)
        {
            return _host.render_icon (resource, size_px, png_path);
        } // render_icon

        /**
         * @brief Stops playback, saves state and quits, whatever the "keep playing" setting is.
         *
         * @param reason Why the application is quitting, for the log.
         */
        public void quit_cleanly (string reason)
        {
            message ("Quitting: %s", reason);
            if (player != null)
                player.stop ();
            all_time.flush ();
            _host.save_view_state ();
            settings.save ();
            _host.quit_application ();
        } // quit_cleanly


#if DEBUG_LOCAL
        /** @brief Development-only: force the online state, to show the offline look in screenshots. */
        public void debug_set_online (bool online)
        {
            network.set_online (online);
        }
#endif


        // ----------------------------------------------------------
        // Construction helpers
        // ----------------------------------------------------------

        /**
         * @brief Create directory structure quietly
         */
        private string? stat_dir (string dir)
        {
            var _dir = File.new_build_filename (dir, _app_id);
            try {
                _dir.make_directory_with_parents ();
            } catch (IOError.EXISTS e) {
            } catch (Error e) {
                warning (@"Stat Directory failed $(e.message)");
                return null;
            }
            return _dir.get_path ();
        } // stat_dir


        /**
         * @brief Prepares the starred data file path under runtime data storage.
         *
         * Requires `data_dir` to already be set. Also attempts one-time migration from the legacy favorites file.
         *
         * @return The target starred data file handle.
         */
        private File setup_runtime_storage ()
        {
            var favorites_file = File.new_build_filename (data_dir, "favorites.json");
            var starred_file   = File.new_build_filename (data_dir, AppConstants.STARRED_FILE);
            migrate_legacy_favorites (favorites_file, starred_file);

            return starred_file;
        } // setup_runtime_storage


        /**
         * @brief Attempts migration from the legacy favorites file to starred file.
         */
        private void migrate_legacy_favorites (File favorites_file, File starred_file)
        {
            try {
                favorites_file.open_readwrite ().close ();
                starred_file.create (NONE);
                favorites_file.copy (starred_file, FileCopyFlags.NONE);
                warning (@"Migrated v1 Favorites to v2 Starred");
            }
            catch (Error e) {
                // Preconditions not met, no migration needed.
            }
        } // migrate_legacy_favorites


        /**
         * @brief Creates the network state, and has the event bus and the HTTP client follow it.
         */
        private NetworkState create_network_state ()
        {
            var state = new NetworkState ();
            state.changed.connect ((online) => {
                events.connectivity_changed_sig (online);
            });
            HttpClient.use_network (state);
            return state;
        } // create_network_state


        /**
         * @brief Initializes connectivity monitor hooks and initial online state.
         */
        private void initialize_connectivity_monitoring ()
        {
            network.set_online (NETMON.get_network_available ());
            NETMON.network_changed.connect ((monitor) => {
                check_online_status ();
            });
        } // initialize_connectivity_monitoring


        /**
         * @brief Set the network availability
         *
         * If going offline, set immediately.
         * Going online - wait a second to allow network to stabilize
         * This method removes any existing timeout and sets a new one
         * reduces network state bounciness
         */
        private void check_online_status ()
        {
            bool network_available = NETMON.get_network_available ();

            // Clean up the prior network monitor task
            if (_monitor_changed_id > 0)
            {
                Source.remove (_monitor_changed_id);
                _monitor_changed_id = 0;
            }

            /*
                If change to online from offline state
                wait 1 seconds before setting to online status
                to whatever the state is at that time
            */
            if (network_available)
            {
                if (is_online)
                    return;

                _monitor_changed_id = Timeout.add_seconds ((uint) _has_started + 1, () =>
                {
                    _monitor_changed_id = 0; // Reset timeout ID after scheduling
                    network.set_online (NETMON.get_network_available ());
                    _has_started = true;
                    return Source.REMOVE;
                });

                return;
            }
            // network is unavailable
            network.set_online (false);
        } // check_online_status
    } // CoreSession
} // Tuner
