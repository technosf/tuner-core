/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024-2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Application.vala
 * @brief Contains the main Application class for the Tuner application
 *
 */

/**
 *
 * @brief Tuner application settings management.
 */
public class Tuner.Settings : GLib.Settings 
{  
    private const string SETTINGS_AUTO_PLAY = "auto-play";
    private const string SETTINGS_DO_NOT_VOTE = "do-not-vote";
    private const string SETTINGS_LAST_PLAYED_STATION = "last-played-station";
    private const string SETTINGS_POS_X = "pos-x";
    private const string SETTINGS_POS_Y = "pos-y";
    private const string SETTINGS_START_ON_STARRED = "start-on-starred";
    private const string SETTINGS_STARTUP_JINGLE = "startup-jingle";
    private const string SETTINGS_STREAM_INFO = "stream-info";
    private const string SETTINGS_STREAM_INFO_FAST = "stream-info-fast";
    private const string SETTINGS_STREAM_INFO_IMAGE_POPUP = "stream-info-image-popup";
    private const string SETTINGS_STREAM_INFO_IMAGE_POPUP_STAY_BACK = "stream-info-image-popup-stay-back";
    private const string SETTINGS_STREAM_INFO_DYNAMIC_SHRINK = "stream-info-dynamic-shrink";
    private const string SETTINGS_THEME_MODE = "theme-mode";
    private const string SETTINGS_LANGUAGE = "language";
    private const string SETTINGS_VOLUME = "volume";
    private const string SETTINGS_WINDOW_HEIGHT = "window-height";
    private const string SETTINGS_WINDOW_WIDTH = "window-width";
    private const string SETTINGS_PLAY_RESTART = "play-restart";
    private const string SETTINGS_PLAY_IN_BACKGROUND = "play-in-background";
    private const string SETTINGS_INHIBIT_SLEEP = "inhibit-sleep";
    private const string SETTINGS_SAVE_ALL_TIME_HEARTED = "save-all-time-hearted";
    private const string SETTINGS_CATEGORY_EXPANDED_MASK = "category-expanded-mask";

    public bool auto_play { get; set; }
    public bool do_not_vote { get; set; }
    public string last_played_station { get; set; }
    public bool start_on_starred { get; set; }
    public bool startup_jingle { get; set; }
    public bool stream_info { get; set; }
    public bool stream_info_fast { get; set; }
    public bool stream_info_image_popup { get; set; }
    public bool stream_info_image_popup_stay_back { get; set; }
    public bool stream_info_dynamic_shrink { get; set; }
    public string theme_mode { get; set; }
    public string language { get; set; }
    public double volume { get; set; }
    public bool play_restart { get; set; }
    public bool play_in_background { get; set; }
    public bool inhibit_sleep { get; set; }
    public bool save_all_time_hearted { get; set; }
    public uint category_expanded_mask { get; set; }

    private int _pos_x;
    private int _pos_y;
    private int _window_height;
    private int _window_width;

    /** 
    * @brief Constructor for the Settings class
    *
    * This constructor initializes the Settings object by calling the parent constructor with the appropriate schema ID.
    * It then loads the settings values from the GSettings backend and assigns them to the corresponding properties of the Settings class. 
    *
    * Settings keyfile file path .var/app/app id/config/glib-2.0/settings/keyfile
    */
    public Settings() 
    {
       Object(
            schema_id : AppConstants.ID
       );

        // Keep simple properties synchronized with GSettings both ways.
        bind (SETTINGS_AUTO_PLAY, this, "auto_play", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_DO_NOT_VOTE, this, "do_not_vote", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_LAST_PLAYED_STATION, this, "last_played_station", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_START_ON_STARRED, this, "start_on_starred", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STARTUP_JINGLE, this, "startup_jingle", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO, this, "stream_info", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_FAST, this, "stream_info_fast", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_IMAGE_POPUP, this, "stream_info_image_popup", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_IMAGE_POPUP_STAY_BACK, this, "stream_info_image_popup_stay_back", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_DYNAMIC_SHRINK, this, "stream_info_dynamic_shrink", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_THEME_MODE, this, "theme_mode", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_LANGUAGE, this, "language", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_VOLUME, this, "volume", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_PLAY_RESTART, this, "play_restart", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_PLAY_IN_BACKGROUND, this, "play_in_background", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_INHIBIT_SLEEP, this, "inhibit_sleep", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_SAVE_ALL_TIME_HEARTED, this, "save_all_time_hearted", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_CATEGORY_EXPANDED_MASK, this, "category_expanded_mask", SettingsBindFlags.DEFAULT);

        _pos_x = get_int(SETTINGS_POS_X);
        _pos_y = get_int(SETTINGS_POS_Y);
        _window_height = get_int(SETTINGS_WINDOW_HEIGHT);
        _window_width = get_int(SETTINGS_WINDOW_WIDTH);

        // Debug hooks to verify category mask tracking in both directions.
        changed.connect ((key) =>
        {
            if (key == SETTINGS_CATEGORY_EXPANDED_MASK) 
            {
                debug (
                    "Settings changed from backend: %s=%u",
                    SETTINGS_CATEGORY_EXPANDED_MASK,
                    get_uint (SETTINGS_CATEGORY_EXPANDED_MASK)
                );
            } // if
        });

        notify["category-expanded-mask"].connect (() =>
        {
            debug (
                "Settings property updated: category_expanded_mask=%u",
                category_expanded_mask
            );
        });

    } // Settings


    /** @brief Saved window position, x. 0 with y 0 means "centre it" */
    public int window_x { get { return _pos_x; } }

    /** @brief Saved window position, y */
    public int window_y { get { return _pos_y; } }

    /** @brief Saved window width, or 0 for the default size */
    public int window_width { get { return _window_width; } }

    /** @brief Saved window height, or 0 for the default size */
    public int window_height { get { return _window_height; } }


    /**
     * @brief Remembers the window position and size and writes them to the settings.
     *
     * The presentation layer reads the geometry from its window (see WindowGeometry in Widgets) and
     * passes it here, so the settings know nothing about windows. The position is only saved when
     * neither coordinate is 0 (0 is read as "centre" on the next launch); the size only when both
     * are above 0, otherwise the last good size is kept.
     */
    public void remember_window_geometry (int x, int y, int width, int height)
    {
        _pos_x = x;
        _pos_y = y;
        if (width > 0 && height > 0)
        {
            _window_width = width;
            _window_height = height;
        }

        if (_pos_x != 0 && _pos_y != 0)
        {
            set_int(SETTINGS_POS_X, _pos_x);
            set_int(SETTINGS_POS_Y, _pos_y);
        }

        if (_window_width > 0 && _window_height > 0)
        {
            set_int(SETTINGS_WINDOW_WIDTH, _window_width);
            set_int(SETTINGS_WINDOW_HEIGHT, _window_height);
        }
    } // remember_window_geometry


    /** @brief Writes the settings out. */
    public void save()
    {
        sync();
    } // save


    /**
     * @brief Persist the source list expansion mask immediately.
     *
     * @param mask Bitmask representing expanded source list sections.
     */
    public void persist_category_expanded_mask (uint mask)
    {
        category_expanded_mask = mask;
        debug (
            "Persisted category_expanded_mask=%u",
            category_expanded_mask
        );
    } // persist_category_expanded_mask


    /** @brief Whether a collapsible source list section is expanded (bit `section` of the saved mask). */
    public bool is_category_expanded (int section)
    {
        return (category_expanded_mask & (1u << section)) != 0;
    } // is_category_expanded


    /** @brief Saves whether a collapsible source list section is expanded, leaving the others as they are. */
    public void set_category_expanded (int section, bool expanded)
    {
        uint mask = category_expanded_mask;
        mask = expanded ? (mask | (1u << section)) : (mask & ~(1u << section));
        persist_category_expanded_mask (mask);
    } // set_category_expanded

} // Tuner.Settings
