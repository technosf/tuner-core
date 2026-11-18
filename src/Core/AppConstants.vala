/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file AppConstants.vala
 *
 * @brief Constants that identify the application, free of any toolkit.
 */

namespace Tuner
{
    /**
     * @class AppConstants
     * @brief Application identity that the functional code may use.
     *
     * These live outside `Application` (a `Gtk.Application`) so that models, services and
     * controllers do not depend on the GTK application class. `Application` keeps its own
     * constants as aliases of these, for the presentation code.
     */
    public class AppConstants : Object
    {
        /** @brief Application ID, also the GSettings schema ID and the name of the data and cache folders */
        public const string ID = "io.github.tuner_labs.tuner";

        /** @brief Application version, from the meson project version */
        public const string APP_VERSION = VERSION;

        /** @brief File name of the starred station store */
        public const string STARRED_FILE = "starred.json";
    } // AppConstants
} // Tuner
