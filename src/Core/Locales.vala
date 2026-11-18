/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Locales.vala
 *
 * @brief Which translations are installed, and the environment variable that selects one.
 */

namespace Tuner
{
    /**
     * @class Locales
     * @brief Installed translations (the languages the user may pick).
     */
    public class Locales : Object
    {
        /** @brief Environment variable gettext reads to choose the language */
        public const string ENV_LANG = "LANGUAGE";

        private static Gee.TreeSet<string>? _found = null;


        /**
         * @brief The locales with an installed translation, plus English.
         *
         * Looked up on first use by listing the locale folder for `GETTEXT_PACKAGE.mo` files.
         */
        public static Gee.Collection<string> found ()
        {
            if (_found == null)
                _found = scan ();
            return _found;
        } // found


        private static Gee.TreeSet<string> scan ()
        {
            var locales = new Gee.TreeSet<string> ();
            locales.add ("en"); // English is always available as default
            try {
                var dir = File.new_for_path (LOCALEDIR);
                var enumerator = dir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
                FileInfo info;
                while ((info = enumerator.next_file ()) != null)
                {
                    if (info.get_file_type () == FileType.DIRECTORY && info.get_name () != "C")
                    {
                        var lang_dir = dir.get_child (info.get_name ());
                        var mo_file = lang_dir.get_child ("LC_MESSAGES").get_child (GETTEXT_PACKAGE + ".mo");
                        if (mo_file.query_exists ())
                            locales.add (info.get_name ());
                    }
                } // while
            } catch (Error e) {
                warning (@"Error reading locale path: $(e.message)");
            }
            return locales;
        } // scan
    } // Locales
} // Tuner
