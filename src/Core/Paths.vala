/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Paths.vala
 *
 * @brief Application folders that the functional code needs.
 */

namespace Tuner
{
    /**
     * @class Paths
     * @brief The application's cache folder, set once at startup.
     *
     * Stations cache their favicons here. It replaces `Application.instance.cache_dir`, so a model
     * does not need the `Gtk.Application` singleton. `CoreSession` sets it when it is created.
     */
    public class Paths : Object
    {
        /** @brief Per-user cache folder of the application, or null if it could not be created */
        public static string? cache_dir = null;
    } // Paths
} // Tuner
