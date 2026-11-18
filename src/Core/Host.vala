/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Host.vala
 *
 * @brief What the core asks of the presentation layer.
 */

using Tuner.Models;

namespace Tuner
{
    /**
     * @interface Host
     * @brief The few things the core asks the presentation layer to do.
     *
     * A presentation layer (today the GTK3 `Application`) implements this and gives it to `CoreSession`.
     * Everything here is a request: the core never reaches for a window or a toolkit itself. Each method
     * must be safe to call before the presentation layer has a window.
     */
    public interface Host : Object
    {
        /** @brief Select and play a station in the main window, once there is one */
        public abstract void play_station_in_ui (Station station);

        /** @brief Bring the main window to the front, if there is one */
        public abstract void present_window ();

        /** @brief Show the starred stations (the start-on-starred setting) */
        public abstract void choose_starred_stations ();

        /** @brief Draw an icon from the app resources to a PNG file; true if the file was written */
        public abstract bool render_icon (string resource, int size_px, string png_path);

        /** @brief Hand the settings whatever view state the presentation layer keeps (window position and size) */
        public abstract void save_view_state ();

        /**
         * @brief Address of the sound to play at start-up, or null if this presentation layer has none.
         *
         * The sound is a resource of the presentation layer, so only it knows where it is.
         */
        public abstract string? startup_sound_uri ();

        /** @brief End the application's main loop */
        public abstract void quit_application ();
    } // Host
} // Tuner
