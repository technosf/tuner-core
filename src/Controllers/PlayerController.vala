/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerController.vala
 */

using Tuner.Events;
using Tuner.Models;
using Tuner.Services;

/**
 * @class Tuner.PlayerController
 * @brief Manages the playback of radio stations.
 *
 * This class handles the player state, volume control, and metadata extraction
 * from the media stream. It emits signals when the station, state, title,
 * or volume changes.
 */
public class Tuner.Controllers.PlayerController : GLib.Object 
{
    private const bool TRACE_METADATA_PATH = false;

    /** @brief Makes the stream player for a URL. The default makes the GStreamer player; tests supply a fake. */
    public delegate StreamPlayer PlayerFactory (string stream_url);

    /** @brief Says whether the machine has a network connection; tests give their own so they do not depend on the machine */
    public delegate bool NetworkProbe ();

    private const uint PLAYING_STATE_DEBOUNCE_MS = 1000;

    public bool play_error { get { return _play_error; } }
    public string? play_error_message { get { return _play_error_message; } }


    /** The error received when playing, if any */
    private bool _play_error = false;
    private string? _play_error_message = null;

    
    private StreamPlayer? _player;
    private Station _station; 
    //private StreamMetadata _metadata;
    private StreamPlayer.State _player_state = StreamPlayer.State.STOPPED;
    private StreamPlayer.State _last_play_state = StreamPlayer.State.STOPPED;
    private double _volume_cache = 0.5;
    private uint _debounce_state_id = 0;


    private AppEventBus _events;
    private Settings _settings;
    private StationSession _session;
    private NetworkState _network;
    private PlayerFactory? _player_factory;
    private NetworkProbe? _network_probe;


    /**
     * @brief Creates the player controller.
     *
     * @param events The event bus, told of playback changes
     * @param settings The settings, which hold the volume
     * @param session The station session, told which stations fail to play
     * @param network The network state, so nothing plays while offline
     * @param player_factory Makes the stream player for a URL, or null for the GStreamer player
     * @param network_probe Says whether the machine has a network, or null to ask the system's network monitor
     */
    public PlayerController (AppEventBus events, Settings settings, StationSession session, NetworkState network,
                             owned PlayerFactory? player_factory = null, owned NetworkProbe? network_probe = null)
    {
        Object ();
        _events = events;
        _settings = settings;
        _session = session;
        _network = network;
        _player_factory = (owned) player_factory;
        _network_probe = (owned) network_probe;
    } // PlayerController


    /** Whether the machine reports a network. This can lag behind the network state the app keeps. */
    private bool machine_has_network ()
    {
        return _network_probe != null ? _network_probe () : NetworkMonitor.get_default ().get_network_available ();
    } // machine_has_network


    /**
     * @brief Process play state changes emitted from the stream player.
     *
     * Actions are normalized in controller space to keep stream implementations simple.
     *
     * @param state The stream player's reported state.
     */
    private void set_play_state (StreamPlayer.State state) 
    {
        if (_player == null)
            return;
        switch (state) {
            case StreamPlayer.State.PLAYING:
                {
                    if (_network.is_offline)
                    {
                        clear_play_error ();
                        _player.stop ();
                        player_state = StreamPlayer.State.STOPPED;
                        break;
                    }
                    clear_play_error ();
                    player_state = StreamPlayer.State.PLAYING;
                }
                break;

            case StreamPlayer.State.BUFFERING:
            case StreamPlayer.State.PAUSED:
                {
                    if ( _network.is_offline)
                    {
                        clear_play_error ();
                        _player.stop ();
                        player_state = StreamPlayer.State.STOPPED;
                        break;
                    }
                    clear_play_error ();
                    player_state = StreamPlayer.State.BUFFERING;
                }
                break;

            default :       //  STOPPED:
                {
                    bool network_available = machine_has_network ();
                    
                    bool offline_or_lost_network = _network.is_offline || !network_available;

                    if ( _play_error && !offline_or_lost_network )
                    {
                        player_state = StreamPlayer.State.STOPPED_ERROR;
                    }
                    else
                    {
                        if (offline_or_lost_network)
                            clear_play_error ();
                        player_state = StreamPlayer.State.STOPPED;
                    }
                }
                break;
        } // switch
    } // set_reverse_symbol


    /** 
     * @brief Player State getter/setter
     * 
     * Set by player signal. Does the tape counter emit
     */
     public StreamPlayer.State player_state { 
        get {
            return _player_state;
        } // get

        private set {
            _player_state = value;
            
            if (_station != null )
                _events.player_state_changed_sig(_station, value);
		} // set
	} // player_state


    /** 
     * @brief Station
     * @return The current station being played.
     */
    public Station station {
        get {
            return _station;
        }
        set {
            if ( ( _station == null ) ||  ( _station != value ) )
            {
                _station = value;
                play_station (_station);
            }
        }
    } // station


    /** 
     * @brief Volume
     * @return The current volume of the player.
     */
    public double volume {
        get { return _player != null ? _player.volume : _volume_cache; }
        set {
            _volume_cache = value;
            if (_player != null)
                _player.set_volume_level (value);
            
                _events.volume_changed_sig (value);
                _settings.volume = value;
        }
    } // volume


    /** How long further station requests are ignored after one is accepted, so stations do not pile up. */
    public const uint STATION_CHANGE_SETTLE_MS = 1200u;

    private bool _changing_station = false;


    /**
     * @brief A station chosen by the user: the entry point for a click on a station.
     *
     * Ignored while offline, when the station is already the one playing (unless it failed), and while an earlier
     * request is still settling. An accepted station is remembered as the last played and is played with a
     * crossfade from the one before it.
     *
     * @param station The station the user chose.
     * @return True if the station was accepted and is now starting.
     */
    public bool request_station (Station station)
    {
        if (_network.is_offline || _changing_station)
            return false;
        bool same = _station != null
            && (_station == station || (_station.stationuuid != "" && _station.stationuuid == station.stationuuid));
        if (same && _player_state != StreamPlayer.State.STOPPED_ERROR)
            return false;

        _changing_station = true;
        Timeout.add (STATION_CHANGE_SETTLE_MS, () =>
        {
            _changing_station = false;
            return Source.REMOVE;
        });

        _settings.last_played_station = station.stationuuid;
        play_station (station);
        return true;
    } // request_station


    /**
    * @brief Plays the specified station.
    *
    * The player will crossfade from the current station to the new one.
    * The current player is detached and a new one created and attached
    *
    * @param station The station to play.
    */
	public void play_station (Station station)
	{
        var previous_player = _player;
        if (Tuner.debug_enabled ())
            debug ("play_station %s (previous player: %s, state: %s)", station.name,
                   previous_player != null ? "yes" : "none", ((int) _player_state).to_string ());
        if (previous_player != null)
            detach_player ();

        _station = station;
        string stream_url = (_station.urlResolved != null && _station.urlResolved != "") ? _station.urlResolved : _station.url;

        _volume_cache = _settings.volume;
        attach_player (_player_factory != null ? _player_factory (stream_url) : Tuner.create_stream_player (stream_url));
        clear_play_error ();
        _station.track_listen ();
        _events.station_changed_sig (_station);
        if (previous_player != null && _player != null)
        {
            if (Tuner.debug_enabled ())
                debug ("play_station: crossfading to %s", station.name);
            previous_player.crossfade_to (_player, _volume_cache);
            return;
        }
		Timeout.add (500, () =>
		// Wait a half of a second to play the station to help flush metadata
		{
            if (_player != null)
			    _player.play ();
			return Source.REMOVE;
		});
	} // play_station


    /**
     * @brief Checks if the player has a station to play.
     *
     * @return True if a station is ready to be played
     */
    public bool can_play () {
        return _station != null;
    } // can_play


    /**
     * @brief Toggles play/pause state of the player.
     */
     public void play_pause () {
        switch (_player_state) {
            case StreamPlayer.State.PLAYING:
            case StreamPlayer.State.BUFFERING:
                if (_player != null)
                    _player.stop ();
                break;
            default:
                clear_play_error ();
                if (_player != null)
                    _player.play ();
                break;
        }
    } // play_pause


    /**
     * @brief Stops the player
     *
     */
    public void stop () {
        if (_player != null)
            _player.stop ();
    } // stop

    /**
     * @brief Connects a new player instance and initializes controller state.
     *
     * @param player The player instance to attach.
     */
    private void attach_player (StreamPlayer player)
    {
        detach_player ();
        _player = player;
        _player.set_volume_level (_volume_cache);
        _last_play_state = StreamPlayer.State.STOPPED;
        _debounce_state_id = 0;
        clear_play_error ();

        _player.play_state_changed_sig.connect (on_player_state_changed);
        _player.stream_metadata_changed_sig.connect (on_player_metadata_changed);
        _player.playback_error_sig.connect (on_player_error);

        on_player_state_changed (_player.play_state);
        on_player_metadata_changed ();
    } // attach_player


    /**
     * @brief Disconnects the current player instance and clears controller state.
     */
    private void detach_player ()
    {
        cancel_state_debounce ();
        if (_player != null)
        {
            _player.play_state_changed_sig.disconnect (on_player_state_changed);
            _player.stream_metadata_changed_sig.disconnect (on_player_metadata_changed);
            _player.playback_error_sig.disconnect (on_player_error);
        }
        _player = null;
    } // detach_player


    /**
     * @brief Handles state change signals from the player.
     *
     * @param state The new player state.
     */
    private void on_player_state_changed (StreamPlayer.State state)
    {
        apply_player_state (state, false);
    } // on_player_state_changed


    /**
     * @brief Applies a player state change with optional debounce override.
     *
     * @param state The player state to apply.
     * @param force True to apply even if the state matches the last seen value.
     */
    private void apply_player_state (StreamPlayer.State state, bool force)
    {
        if (!force && state == _last_play_state)
            return;
        _last_play_state = state;

        if (state == StreamPlayer.State.PLAYING)
        {
            cancel_state_debounce ();
            set_play_state (StreamPlayer.State.PLAYING);
            return;
        }

        if (state == StreamPlayer.State.BUFFERING
            || state == StreamPlayer.State.PAUSED)
        {
            if (_player_state == StreamPlayer.State.PLAYING && !force)
            {
                schedule_state_debounce ();
            }
            else
            {
                set_play_state (StreamPlayer.State.BUFFERING);
            }
            return;
        }

        cancel_state_debounce ();
        set_play_state (StreamPlayer.State.STOPPED);
    } // apply_player_state


    /**
     * @brief Schedules a short debounce before applying a non-playing state.
     */
    private void schedule_state_debounce ()
    {
        if (_debounce_state_id > 0)
            return;
        _debounce_state_id = Timeout.add (PLAYING_STATE_DEBOUNCE_MS, () => 
            {
                _debounce_state_id = 0;
                var player = _player;
                if (player == null)
                    return Source.REMOVE;
                apply_player_state (player.play_state, true);
                return Source.REMOVE;
            });
    } // schedule_state_debounce


    /**
     * @brief Cancels any pending debounce timer.
     */
    private void cancel_state_debounce ()
    {
        if (_debounce_state_id > 0)
        {
            Source.remove (_debounce_state_id);
            _debounce_state_id = 0;
        }
    } // cancel_state_debounce

    
    /**
     * @brief Handles updated metadata from the player.
     *
     * @param metadata The metadata table provided by the player.
     */
    private void on_player_metadata_changed ()
    {
        if (_player == null || _station == null)
            return;

        if (TRACE_METADATA_PATH)
        {
            stdout.printf (
                "[TRACE][PlayerController] emit playback_metadata station=%s title='%s' pretty_len=%u\n",
                _station.stationuuid,
                _player.stream_metadata.title,
                _player.stream_metadata.pretty_print.length
            );
        }

        _events.playback_metadata_changed_sig (_station, _player.stream_metadata);

    } // on_player_metadata_changed


    /**
     * @brief Handles playback errors reported by the player.
     *
     * @param _message The error message reported by the player.
     */
    private void on_player_error (string _message)
    {
        // One failure raises several errors in a row (e.g. HTTP 403, then "internal data stream
        // error", then "can't typefind"). The first is the root cause - keep it for the tooltip
        // and treat the rest as follow-on noise until the error is cleared by the next play.
        if (!_play_error)
        {
            _play_error = true;
            _play_error_message = _message;

            // A failure while offline or without a network says nothing about the station
            bool offline_or_lost_network = _network.is_offline || !machine_has_network ();
            if (_station != null && !offline_or_lost_network)
                _session.mark_broken (_station, _message);
        }
        else
        {
            if (Tuner.debug_enabled ())
                debug (@"Ignoring follow-on playback error: $(_message)");
        }

        set_play_state (StreamPlayer.State.STOPPED_ERROR);
    } // on_player_error


    /**
     * @brief Clears stored playback error state and message.
     */
    private void clear_play_error ()
    {
        _play_error = false;
        _play_error_message = null;
    } // clear_play_error


    /**
     * Shuffles the current playlist.
     *
     * This method randomizes the order of the tracks in the current playlist.
     */
	public void shuffle ()
	{
		_events.shuffle_requested_sig();
	} // shuffle
} // PlayerController
