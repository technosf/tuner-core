/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Utils.vala
 *
 * @brief Utility functions for the Tuner radio application
 */

 using GLib;
 using Tuner.Models;
 using Tuner.Ext;

/**
 * @namespace Tuner
 * @brief Main namespace for the Tuner application
 */
namespace Tuner {


    /**
     * @brief Build the app-wide User-Agent string.
     */
    public static string user_agent ()
    {
        return UserAgent.get_string ();
    } // user_agent


    /**
     * @class UserAgent
     * @brief The User-Agent Tuner sends on every HTTP request: to radio-browser.info, for favicons, and to streams.
     *
     * Form: `<app id>/<app version> (pkg: <packaging>; os: <distribution>) tuner-core/<core version>`, for
     * example `io.github.tuner_labs.tuner/0.1.0 (pkg: flatpak; os: org.freedesktop.platform) tuner-core/0.1.0`.
     * It lets the directory (and stream owners) tell which builds and packagings are out there, and fix
     * or contact a packager when one misbehaves. It carries nothing about the user or the machine
     * beyond the distribution's id.
     *
     * The presentation layer calls `configure()` once, before the first request, with its own version and the
     * packaging chosen at build time (meson option `packaging`). When no packaging was given it is detected:
     * Flatpak, Snap, AppImage, else "source" for a build that nobody has labelled.
     */
    public class UserAgent : Object
    {
        private static string _app_version = AppConstants.APP_VERSION;
        private static string _packaging = "";
        private static string? _cached = null;

        /**
         * @brief Sets what the User-Agent says about the app. Call before the first request.
         *
         * @param app_version the presentation layer's version
         * @param packaging   how this build was packaged ("deb", "rpm", "aur", "nix", "flatpak", ...), "" to detect it
         */
        public static void configure (string app_version, string packaging)
        {
            _app_version = token (app_version, "unknown");
            _packaging   = token (packaging, "");
            _cached      = null;
        } // configure


        /** @brief The User-Agent string. */
        public static string get_string ()
        {
            if (_cached == null)
            {
                var pkg = _packaging != "" ? _packaging : detect_packaging ();
                var os  = token (os_id (), "unknown");
                _cached = @"$(AppConstants.ID)/$(_app_version) (pkg: $pkg; os: $os) tuner-core/$(CORE_VERSION)";
            }
            return _cached;
        } // get_string


        /** @brief The ID= of os-release (the distribution, or in a Flatpak the runtime); "" if it cannot be read. */
        private static string os_id ()
        {
            foreach (var path in new string[] { "/etc/os-release", "/usr/lib/os-release" })
            {
                string contents;
                try
                {
                    if (!GLib.FileUtils.get_contents (path, out contents))
                        continue;
                }
                catch (GLib.FileError e)
                {
                    continue;
                }

                foreach (var line in contents.split ("\n"))
                {
                    if (line.has_prefix ("ID="))
                        return line.substring (3).replace ("\"", "").replace ("'", "");
                }
            }
            return "";
        } // os_id


        /** @brief Which sandbox or bundle we are running in, when the build was not labelled. */
        private static string detect_packaging ()
        {
            if (GLib.FileUtils.test ("/.flatpak-info", GLib.FileTest.EXISTS) || GLib.Environment.get_variable ("FLATPAK_ID") != null)
                return "flatpak";
            if (GLib.Environment.get_variable ("SNAP_NAME") != null)
                return "snap";
            if (GLib.Environment.get_variable ("APPIMAGE") != null)
                return "appimage";
            return "source";
        } // detect_packaging


        /** @brief Lower-case, and only characters that are safe in a header comment; `fallback` when nothing is left. */
        private static string token (string text, string fallback)
        {
            var sb = new StringBuilder ();
            var clean = text.strip ().down ();
            for (int i = 0; i < clean.length; i++)
            {
                char c = clean[i];
                if (c.isalnum () || c == '.' || c == '-' || c == '_' || c == '+')
                    sb.append_c (c);
                else if (sb.len > 0 && sb.str[sb.len - 1] != '-')
                    sb.append_c ('-');
            }
            return sb.len > 0 ? sb.str : fallback;
        } // token
    } // UserAgent


    /**
     * @brief Formats a length of time as H:MM:SS, or M:SS when it is under an hour.
     */
    public static string format_duration (int total_seconds)
    {
        int hours = total_seconds / 3600;
        int minutes = (total_seconds % 3600) / 60;
        int seconds = total_seconds % 60;

        if (hours > 0)
            return "%d:%02d:%02d".printf (hours, minutes, seconds);

        return "%d:%02d".printf (minutes, seconds);
    } // format_duration


    private static int _debug_state = -1;      // -1 unknown, 0 off, 1 on

    /**
     * @brief Whether debug logging is switched on (`G_MESSAGES_DEBUG` is set).
     *
     * Vala builds `debug(@"...")` strings before `debug()` can decide to drop them.
     * On hot paths (every HTTP request, every tick) guard the call with this so the
     * string is only built when someone is going to read it:
     * `if (Tuner.debug_enabled ()) debug(@"...");`
     */
    public static bool debug_enabled ()
    {
        if (_debug_state < 0)
        {
            var domains = Environment.get_variable ("G_MESSAGES_DEBUG");
            _debug_state = (domains != null && domains != "") ? 1 : 0;
        }
        return _debug_state == 1;
    } // debug_enabled


    /**
    * @brief Send the calling method for a nap
    *
    * @param interval the time to nap
    * @param priority priority of checking nap is over
    */
    public static async void nap (uint interval) {
        Timeout.add (interval, () => {
            nap.callback ();
            return Source.REMOVE;
        }, Priority.LOW);
        yield;
    } // nap


    /**
     * @brief Percent-encodes text for use in a URI query.
     *
     * Everything except the unreserved characters (letters, digits, - . _ ~) is encoded, so any
     * text, including spaces, quotes, brackets, backslashes and non-ASCII characters, makes a valid
     * URI. Without this such text produced an invalid URI and a libsoup "soup_uri_is_valid" critical.
     *
     * @param text The text to encode.
     * @param keep Characters to leave as they are, for example a separator the receiving API
     *             understands. Empty by default: nothing extra is kept.
     * @return The percent-encoded text.
     */
    public static string encode_text( string text, string keep = "" )
    {
        return Uri.escape_string (text, keep, false);
    } // encode_text


    /**
     * Safely strips whitespace from a string, handling null and empty strings.
     * @param text The string to strip.
     * @return The stripped string or an empty string if input is null or empty.
     */
    public static unowned string safestrip( string? text )
    {
        if ( text == null ) return "";
        if ( text.length == 0 ) return "";
        return text._strip();
    } // safestrip


    /**
     * @brief Create a stream player for the given URL.
     *
     * Centralizes the selection of the concrete StreamPlayer implementation.
     *
     * @param stream_url Stream URL to play.
     * @return A StreamPlayer instance for the requested URL.
     */
    public static StreamPlayer create_stream_player (string stream_url)
    {
        return new GstStreamPlayer (stream_url);
    } // create_stream_player


    /**
     * @brief Play a file URI through the configured stream backend.
     *
     * Centralizes one-shot playback mapping so `StreamPlayer` remains backend-agnostic.
     *
     * @param file_uri URI to play.
     * @param volume Playback volume between 0.0 and 1.0.
     * @param on_finished Optional callback fired on EOS/ERROR.
     * @return Backend playback handle, or null when setup failed.
     */
    public static GLib.Object? play_stream_file (string file_uri, double volume, owned StreamPlayer.FilePlaybackFinished? on_finished = null)
    {
        return GstStreamPlayer.play_file_backend (file_uri, volume, (owned) on_finished);
    } // play_stream_file

} // namespace Tuner
