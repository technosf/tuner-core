/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file AppContext.vala
 *
 * @brief What the functional code needs from the running application, as an interface.
 */

using Tuner.Events;
using Tuner.Models;
using Tuner.Controllers;
using Tuner.Coordinators;

namespace Tuner
{
    /**
     * @interface AppContext
     * @brief The application as seen by controllers, coordinators and services.
     *
     * Before this, those classes took the `Gtk.Application` subclass `Application` directly, which tied
     * the functional code to GTK and to the main window. They now take this interface instead, and the
     * GTK `Application` implements it.
     *
     * Read-only members hand out the shared services. The methods are the few things the functional
     * code asks the presentation layer to do: show a station, raise the window, quit. This is the
     * "Host" of SEPARATION_PLAN.md in its first form; the services now live in
     * `CoreSession` (which implements this) and the methods are forwarded to the presentation layer's `Host`.
     */
    public interface AppContext : Object
    {
        /** @brief App-wide event bus */
        public abstract AppEventBus events { get; }

        /** @brief Per-session station state, such as stations that failed to play */
        public abstract StationSession session { get; }

        /** @brief Play history */
        public abstract History history { get; }

        /** @brief Playback controller */
        public abstract PlayerController player { get; }

        /** @brief Jukebox controller */
        public abstract JukeboxController jukebox { get; }

        /** @brief Network and radio-browser connection state machine */
        public abstract ConnectionCoordinator connection { get; }

        /** @brief True when the network is available */
        public abstract bool is_online { get; }

        /** @brief True when the network is not available */
        public abstract bool is_offline { get; }

        /** @brief Per-user cache folder, or null if it could not be created */
        public abstract string? cache_dir { get; }

        /**
         * @brief Stops playback, saves state and quits, whatever the "keep playing" setting is.
         *
         * @param reason Why the application is quitting, for the log.
         */
        public abstract void quit_cleanly (string reason);

        /**
         * @brief Asks the presentation layer to select and play a station.
         *
         * Does nothing if there is no window yet.
         */
        public abstract void play_station_in_ui (Station station);

        /**
         * @brief Asks the presentation layer to bring the main window to the front, if there is one.
         */
        public abstract void present_window ();

        /**
         * @brief Asks the presentation layer to show the starred stations (the start-on-starred setting).
         *
         * Safe to call before the window is active; the choice is remembered until it is.
         */
        public abstract void choose_starred_stations ();

        /**
         * @brief Asks the presentation layer to draw an icon from the app resources to a PNG file.
         *
         * @return true if the file was written
         */
        public abstract bool render_icon (string resource, int size_px, string png_path);
    } // AppContext
} // Tuner
