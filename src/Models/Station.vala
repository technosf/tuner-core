/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Station.vala
 *
 * @brief Station metadata and related cachable objects
 * 
 */

using Gee;

/**
 * @class Station
 * @brief Represents a radio station with various properties.
 */
public class Tuner.Models.Station : Favicon
{

    // ----------------------------------------------------------
    // statics
    // ----------------------------------------------------------

    // Stations with Favicons that failed to load
    //  private static Set<string> STATION_FAILING_FAVICON = new HashSet<string>();

    // Core set of all station so far retrieved
    private static Map<string,Station> STATIONS = new HashMap<string,Station>();


    // Signals
    public signal void station_star_changed_sig( bool starred );  // Station starred state has changed


    // ----------------------------------------------------------
    // Properties
    // ----------------------------------------------------------

    /** @property {string} changeuuid - Unique identifier for the change. */
    public string 	changeuuid	{ get; private set; }
    /** @property {string} stationuuid - Unique identifier for the station. */
    public string   stationuuid	{ get; private set; }
    /** @property {string} name - Name of the station. */
    public string	name	{ get; private set; }
    /** @property {string} url - URL of the station stream. */
    public string	url	{ get; private set; }
    /** @property {string} url_resolved - Resolved URL of the station stream. Camel case so goobject serialize is OK*/
    public string	urlResolved	{ get; private set; }
    /** @property {string} homepage - Homepage of the station. */
    public string	homepage	{ get; private set; }
    /** @property {string} favicon - Favicon URL of the station. */
    //  public string	favicon	{ get; private set ; }
    /** @property {string} tags - Tags associated with the station. */
    public string	tags	{ get; private set ; }
    /** @property {string} country - Country where the station is located. */
    public string	country	{ get; private set ; }
    /** @property {string} countrycode - Country code of the station. */
    public  string	countrycode	{ get; private set ; }
    /** @property {string} iso_3166_2 - ISO 3166-2 code for the station's location. */
    public string	iso_3166_2  { get; private set ; }
    /** @property {string} state - State where the station is located. */
    public string	state	{ get; private set ; }
    /** @property {string} language - Language of the station. */
    public string	language	{ get; private set ; }
    /** @property {string} languagecodes - Language codes associated with the station. */
    public string	languagecodes	{ get; private set ; }
    /** @property {string} codec - Audio codec used by the station. */
    public string	codec	{ get; private set ; }
    /** @property {int} bitrate - Bitrate of the station stream. */
    public int	bitrate { get; private set ; }
    /** @property {int} hls - HLS status of the station. */
    public int	hls { get; private set ; }


    // ----------------------------------------------------------
    // Index Properties
    // ----------------------------------------------------------

    /** @property {int} votes - Number of votes for the station. */
    public int	votes { get; set ; }
    /** @property {string} lastchangetime - Last change time of the station. */
    public string	lastchangetime { get; private set ; }
    /** @property {string} lastchangetime_iso8601 - Last change time in ISO 8601 format. */
    public string	lastchangetime_iso8601 { get; private set ; }
    /** @property {int} lastcheckok - Status of the last check (0 or 1). */
    public int    lastcheckok { get; private set ; }
    /** @property {string} lastchecktime - Last check time of the station. */
    public string	lastchecktime { get; private set ; }
    /** @property {string} lastchecktime_iso8601 - Last check time in ISO 8601 format. */
    public string	lastchecktime_iso8601 { get; private set ; }
    /** @property {string} lastcheckoktime - Last successful check time. */
    public string	lastcheckoktime	{ get; private set ; }
    /** @property {string} lastcheckoktime_iso8601 - Last successful check time in ISO 8601 format. */
    public string	lastcheckoktime_iso8601 { get; private set ; }
    /** @property {string} lastlocalchecktime - Last local check time. */
    public string	lastlocalchecktime { get; private set ; }
    /** @property {string} lastlocalchecktime_iso8601 - Last local check time in ISO 8601 format. */
    public string	lastlocalchecktime_iso8601 { get; private set ; }
    /** @property {string} clicktimestamp - Timestamp of the last click. */
    public string	clicktimestamp { get; private set ; }
    
    /** @property {string} clicktimestamp_iso8601 - Last click timestamp in ISO 8601 format. */
    public string	clicktimestamp_iso8601 { get; private set ; }

    /** @property {int} clickcount - Number of clicks on the station. */
    public int	clickcount { get;  set ; }
    /** @property {int} clicktrend - Trend of clicks on the station. */
    public int	clicktrend { get;  set ; }
    /** @property {int} ssl_error - SSL error status. */
    public int    ssl_error { get; private set ; }
    /** @property {string} geo_lat - Latitude of the station's location. */
    public string	geo_lat { get; private set ; }
    /** @property {string} geo_long - Longitude of the station's location. */
    public string	geo_long { get; private set ; }
    /** @property {bool} has_extended_info - Indicates if extended info is available. */
    public bool	    has_extended_info { get; private set ; }
    

    // ----------------------------------------------------------
    // User Properties
    // ----------------------------------------------------------

    /*
        StarStore saves stations with Json.gobject_serialize, which cannot write a GDateTime
        (it logs "Boxed type 'GDateTime' is not handled by JSON-GLib" and drops the value).
        So the two times are held as DateTime but exposed to the serializer as ISO 8601 strings,
        which are saved in the favourites file and read back by Station.basic.
        Use get_starred_since() / get_last_played() for the DateTime values.
    */
    private DateTime? _starred_since = null;
    private DateTime? _last_played = null;

    /** @brief When the station was first starred, or null. */
    public DateTime? get_starred_since () { return _starred_since; }

    /** @brief When the station was last played (counted once per calendar day), or null. */
    public DateTime? get_last_played () { return _last_played; }

    /** @property {string} starred_since_iso8601 - Saved form of get_starred_since(); empty if never starred. Read only. */
    public string starred_since_iso8601
    {
        owned get { return _starred_since != null ? _starred_since.format_iso8601 () : ""; }
    }

    /** @property {string} last_played_iso8601 - Saved form of get_last_played(); empty if never played. Read only. */
    public string last_played_iso8601
    {
        owned get { return _last_played != null ? _last_played.format_iso8601 () : ""; }
    }

    private bool _starred;
    /** @property {bool} starred - Indicates if the station is starred. Only set by Favorites*/
    public bool starred { 
        get { return _starred; }
        set { 
            if ( _starred == value ) return;
            _starred = value; 
            station_star_changed_sig(_starred );
            if ( _starred_since == null ) _starred_since = new DateTime.now_local();
        }
    } // starred


    /**
     * @brief Annotate a Listen to the station 
     */
    public void track_listen()
    {
        var now = new DateTime.now_local();
        if ( _last_played == null || !is_same_calendar_day(_last_played, now) ) 
        {
            _last_played = now;
            days_played += 1;
        }
    } // listen 
    
    public int days_played { get; private set ; }   // Count once per day

    
    // ----------------------------------------------------------
    // Temporal Properties
    // ----------------------------------------------------------

    public bool is_in_index;    // Indicates if the station is in the provider index
    public bool is_up_to_date;  // Indicates if the station is up-to-date with the provider index
    public string up_to_date_difference = _("Station no longer in the index");
    


    // ----------------------------------------------------------
    // Privates
    // ----------------------------------------------------------
    
    //  private Uri _favicon_uri;
    //  private Gdk.Pixbuf _favicon_pixbuf; // Favicon for this station
    private string _favicon_cache_file;

    /**
     * @brief Read an ISO 8601 time saved in the favourites file.
     *
     * @return The time, or null if the member is missing, empty or not a valid time.
     */
    private static DateTime? read_saved_time(Json.Object json_object, string hyphen_name, string underscore_name)
    {
        string name = json_object.has_member(hyphen_name) ? hyphen_name : underscore_name;
        if (!json_object.has_member(name))
            return null;

        var text = json_object.get_string_member(name);
        if (text == null || text.strip() == "")
            return null;

        return new DateTime.from_iso8601(text.strip(), null);   // null when unparseable
    } // read_saved_time

    private bool is_same_calendar_day(DateTime left, DateTime right)
    {
        return left.get_year() == right.get_year()
            && left.get_month() == right.get_month()
            && left.get_day_of_month() == right.get_day_of_month();
    }

    string _locale; // Cached locale string for display

    // ----------------------------------------------------------
    // Functions
    // ----------------------------------------------------------

	/**
	* @brief Returns a unique, initiated Station instance for a given JSON node.
	*
	* If station has already been initiated based on stationuuid, returns the existing Station
    * Checks with StarStore and sets stations starred status
	*
	* @param {Json.Node} json_node - The JSON node containing station data.
	* @param {StarStore} stars - Star store to check the starred status against, or null.
	* @return {Station} The created Station instance.
	*/
	public static Station make(Json.Node json_node, Tuner.Services.StarStore? stars = null)
	{
		Station station = new Station.basic(json_node);
		station.is_in_index           = true;
		station.is_up_to_date         = true; // Assume loaded from the provider as we're adding this to the list
		station.up_to_date_difference = "";
        station.starred = stars != null && stars.contains(station);

        if ( !STATIONS.has_key(station.stationuuid)) 
        /*
            Add station to the index and kickoff async load of the favicon
        */
        {
            STATIONS.set(station.stationuuid,station);
            station.load_favicon_async.begin();
        }

        return STATIONS.get(station.stationuuid);
    } // make

    
     /**
     * @brief Constructor a basic Station instance from a JSON node.
     *
     * @param {Json.Node} json_node - The JSON node containing station data.
     */
     public Station.basic(Json.Node json_node) 
     {
        Object();   

        if ( json_node == null )
        {
            warning(@"Station - no JSON");
            return;
        }

        Json.Object json_object = json_node.get_object();

        //
        // Json is noisy as fields may/may not be returned. Turn off the logging while parsing.
        //
        var log_handler_1 = GLib.Log.set_handler(
                 "Json",
                 GLib.LogLevelFlags.LEVEL_CRITICAL,
                 (log_domain, log_level, message) => {
                     // Ignore the warnings
                 }
             );

		try
		{
			// Deserialize properties manually
			// Put in a try/finally as much for visuals as anything
			changeuuid                 = string_member (json_object, "changeuuid");
			stationuuid                = string_member (json_object, "stationuuid");
			name                       = string_member (json_object, "name");
			url                        = string_member (json_object, "url");
			urlResolved                = string_member (json_object, "url_resolved");
			homepage                   = string_member (json_object, "homepage");
			favicon                    = string_member (json_object, "favicon");
			tags                       = string_member (json_object, "tags");
			country                    = string_member (json_object, "country");
			countrycode                = string_member (json_object, "countrycode");
			iso_3166_2                 = string_member (json_object, "iso_3166_2");
			state                      = string_member (json_object, "state");
			language                   = string_member (json_object, "language");
			languagecodes              = string_member (json_object, "languagecodes");
			votes                      = (int)json_object.get_int_member("votes");
			lastchangetime             = string_member (json_object, "lastchangetime");
			lastchangetime_iso8601     = string_member (json_object, "lastchangetime_iso8601");
			codec                      = string_member (json_object, "codec");
			bitrate                    = (int)json_object.get_int_member("bitrate");
			hls                        = (int)json_object.get_int_member("hls");
			lastcheckok                = (int)json_object.get_int_member("lastcheckok");
			lastchecktime              = string_member (json_object, "lastchecktime");
			lastchecktime_iso8601      = string_member (json_object, "lastchecktime_iso8601");
			lastcheckoktime            = string_member (json_object, "lastcheckoktime");
			lastcheckoktime_iso8601    = string_member (json_object, "lastcheckoktime_iso8601");
			lastlocalchecktime         = string_member (json_object, "lastlocalchecktime");
			lastlocalchecktime_iso8601 = string_member (json_object, "lastlocalchecktime_iso8601");
			clicktimestamp             = string_member (json_object, "clicktimestamp");
			clicktimestamp_iso8601     = string_member (json_object, "clicktimestamp_iso8601");
			clickcount                 = (int)json_object.get_int_member("clickcount");
			clicktrend                 = (int)json_object.get_int_member("clicktrend");
			ssl_error                  = (int)json_object.get_int_member("ssl_error");
			geo_lat                    = string_member (json_object, "geo_lat");
			geo_long                   = string_member (json_object, "geo_long");
			has_extended_info          = json_object.get_boolean_member("has_extended_info");

			var go_serial_fudge = string_member (json_object, "urlResolved"); // Serialization camelcase fudge
			if (go_serial_fudge != null && go_serial_fudge != "")
			{
				urlResolved = go_serial_fudge;
			}

			// Process favorites
			if (json_object.has_member("starred"))
			{
				_starred = json_object.get_boolean_member("starred");
			}

			// User history saved with the favourite. Json.gobject_serialize writes property names
			// with hyphens; accept underscores too.
			_starred_since = read_saved_time(json_object, "starred-since-iso8601", "starred_since_iso8601");
			_last_played   = read_saved_time(json_object, "last-played-iso8601", "last_played_iso8601");
			if (json_object.has_member("days-played"))
				days_played = (int) json_object.get_int_member("days-played");
			else if (json_object.has_member("days_played"))
				days_played = (int) json_object.get_int_member("days_played");

            /* -----------------------------------------------------------------------
                Process v1 Attribute, if any, from old Favorites format
            ----------------------------------------------------------------------- */

            if (json_object.has_member("id") )
            {
                stationuuid = string_member (json_object, "id");
            }             

            if (json_object.has_member("favicon-url") )
            {                
                favicon = string_member (json_object, "favicon-url");
            }       

            if (json_object.has_member("location") )
            {                
                country = string_member (json_object, "location");
            }        

            if (json_object.has_member("title") )
            {                
                name = string_member (json_object, "title");
            }        
        } finally {
            GLib.Log.remove_handler("Json", log_handler_1);
        }

        is_in_index = false; // Basic station creation - assume not in provider index
        is_up_to_date = false; // Basic station creation - assume not up-to-date with provider

		/*
		    Favicon load
		 */
         _favicon_cache_file = Path.build_filename(Paths.cache_dir, stationuuid);
        load_favicon_async.begin();
    } // Station.basic


    /**
     * @brief A string member of a station's JSON, stripped; "" if it is missing or null.
     *
     * The directory returns null for fields it has no value for, and the member is absent in older favourites files.
     */
    private static string string_member (Json.Object json_object, string name)
    {
        if (!json_object.has_member (name) || json_object.get_null_member (name))
            return "";
        var value = json_object.get_string_member (name);   // Null too if the member is not a string
        return value != null ? value.strip () : "";
    } // string_member


    /**
     * @brief Toggles the Starred status of the station
     * @return {bool} True if Station is Starred.
     */
    public bool toggle_starred()
    {
        starred = !starred;
        return _starred;
    } // toggle_starred


    /**
     * @brief Returns a string representation of the station.
     * @return {string} A string in the format "[id] title".
     */
    public string popularity() {
        // TRANSLATORS: Station popularity. The three %d are the number of votes, the number of clicks and the click trend. Keep the tabs
        return _("Votes: %d\t Clicks: %d\t Trend: %d").printf (votes, clickcount, clicktrend);
    } // to_string


    /**
     * @brief Returns a string representation of the station's locale information.
     * @return {string} A string in the format "Country: %s\tState: %s\tLanguage: %s".
     */
    public string locale()
    { 
        if ( ( _locale == null || _locale != "" ) )
        {
            var sb = new StringBuilder ();
        
            // Country
            if ( countrycode != null && countrycode.length > 0 )
            {
                sb.append(Countries.get_by_code(countrycode) + "\n");
                if ( state != null && state.length > 0 )
                sb.append (state).append ("\t");
            }

            // Language
            if ( language != null && language.length > 0 )
            {
                sb.append ("[")
                .append (Languages.get_by_code ( languagecodes,  language))
                .append ("]");
            }
            _locale = sb.str;
        }
        
        return _locale;
        
    } // locale
    

    /**
     * @brief Returns a string representation of the station's temporal information.
     * @return {string} A string in the format "Last Played: %s\tPlays: %d".
     */
    public string temporal()
    {
        // TRANSLATORS: Station summary. %s is the date the station was last played (or a dash), %d the number of days it was played. Keep the tab
        return _("Last Played: %s\tPlays: %d").printf(_last_played != null ? _last_played.format("%x") : "-", days_played);
    } // temporal


    /**
     * @brief Returns a string representation of the station.
     * @return {string} A string in the format "[id] title".
     */
    public string to_string() {
        return @"[$(stationuuid)] $(name)";
    } // to_string


    /**
     * @brief Sets the station up-to-date status based on the given station.
     *
     * @param {Station} p - The station to compare with.
     * @return {bool} True if the station is up-to-date with the given station.
     */
    public bool set_up_to_date_with(Station? p) 
    { 
        if ( p == null || this.stationuuid != p.stationuuid) return false;
        if ( 
            ( this.url == p.url) 
            && (this.bitrate == p.bitrate) 
            && ( this.codec == p.codec)
            //  && (this.changeuuid == p.changeuuid) // TODO Radio browser changeuuids broken
            ) 
        { 
            is_up_to_date = true; 
            up_to_date_difference = "";
        }
        else
        {   
            StringBuilder sb = new StringBuilder(_("Changes")+":");
            if ( this.url != p.url) sb.append("\n\t").append(_("Stream Url"));
            if ( this.urlResolved != p.urlResolved) sb.append("\n\t").append(_("Stream Resolved Url"));
            if ( this.favicon != p.favicon) sb.append("\n\t").append(_("Favicon address"));
            if ( this.homepage != p.homepage) sb.append("\n\t").append(_("Homepage address"));
            if ( this.tags != p.tags) sb.append("\n\t").append(_("Station tags"));
            if ( this.bitrate != p.bitrate) sb.append("\n\t").append(_("Bitrate")).append(": $(this.bitrate) > $(p.bitrate)");
            if ( this.codec != p.codec) sb.append("\n\t").append(_("Codec")).append(": $(this.codec) > $(p.codec)");
            //  if (this.changeuuid != p.changeuuid) sb.append(_("\nOther minor items have changed"));
            //  sb.append(@"\n\n stationuuid: $(p.stationuuid) - $(this.stationuuid) ");
            //  sb.append(@"\n\n changeuuid: $(p.changeuuid) - $(this.changeuuid) ");
            //  sb.append(@"\n\n urlResolved: $(p.urlResolved) - $(this.urlResolved) ");
            //  warning(@"$name $(p.stationuuid) - $(this.stationuuid)\n$(p.changeuuid) - $(this.changeuuid)");
            //  sb.append(@"\n\n changeuuid: $(p.changeuuid) - $(this.changeuuid) ");
            up_to_date_difference = sb.str;
            is_up_to_date = false;
        }
        return true;
    } // set_up_to_date_with


    /**
     * Returns a copy of the current station from the Provider.
     * 
     * @return A new {@link Station} instance with the current properties
     */
    public Station updated()
    {
        return STATIONS.get(stationuuid);
    } // updated

    
    /**
     * @brief Compares this station with another station.
     * @param other The station to compare with.
     * @return {bool} True if stations are equal.
     */
    public bool equals(Station other)
    {
        return this.stationuuid == other.stationuuid;
    } // equals

    
    /**
     * @brief Returns the file path of the favicon cache.
     * @return A string representing the file path of the favicon cache.
     */
    protected override string favicon_cache_file()
    {
        return _favicon_cache_file;
    } // favicon_cache_file
} // Station
