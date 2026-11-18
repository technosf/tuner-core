/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Favicon.vala
 *
 * @brief Favicon index, loading and caching
 * 
 */

using Gee;
using Tuner.Services;

/**
 * @class Favicon
 *
 * @brief Favicon location, download and caching for implementing classes.
 *
 * The class never decodes an image: it downloads the bytes, keeps them in the cache file, and leaves the
 * decoding to the presentation layer. The presentation layer may hand in a check that a download really is
 * an image (Favicon.image_check) and may park its decoded image on the favicon (image_cache).
 *
 * @extends Object
 */
public abstract class Tuner.Models.Favicon : Object
{
    /** @brief Tells whether a downloaded file is a usable image. Set by the presentation layer; null accepts any file. */
    public delegate bool ImageCheck (string path);

    public signal void favicon_sig();  // Station favicon loaded

    // ----------------------------------------------------------
    // statics
    // ----------------------------------------------------------

    /** @brief The presentation layer's check that a downloaded file is an image, if it has one. */
    public static ImageCheck? image_check = null;

    // Stations with Favicons that failed to load
    private static Set<string> FAILING_FAVICON = new HashSet<string>();

    // Largest favicon download kept; a bigger one is treated as a failure
    private const int MAX_FAVICON_BYTES = 2 * 1024 * 1024;
    private const int READ_CHUNK_BYTES = 16 * 1024;


    // ----------------------------------------------------------
    // Properties
    // ----------------------------------------------------------


    /** @property {string} favicon - Favicon URL of the station. */
    private string _favicon;

    /**
     * @brief Favicon URL. Empty values and repeats are ignored. A URL that fails to parse is added to FAILING_FAVICON.
     */
    public string favicon {
        get { return _favicon; }
        protected set {
            if ( value == null || value.length == 0 || _favicon == value ) return;            
            _favicon = value;	
            try	            
            {
                _favicon_uri = Uri.parse(value, NONE);
            } catch (GLib.UriError e)
            {
                FAILING_FAVICON.add(value);
            }
        }
    } // favicon

    /**
     * @brief Room for the presentation layer's decoded image of this favicon.
     *
     * The core never looks inside it. It is cleared whenever the favicon file is replaced.
     */
    public Object? image_cache { get; set; default = null; }


    // ----------------------------------------------------------
    // Privates
    // ----------------------------------------------------------
    
    private Uri _favicon_uri;
    private int _favicon_loaded = 0;  // Indicates the number of load attempts the favicon from cache or internet


    // ----------------------------------------------------------
    // Methods
    // ----------------------------------------------------------

    /**
     * @brief Abstract method to get the file path of the favicon cache.
     *
     * This method should be implemented by subclasses to provide the specific
     * file path where the favicon cache is stored.
     *
     * @return A string representing the file path of the favicon cache.
     */
    protected abstract string favicon_cache_file();

    
    /**
     * @brief Has favicon been loaded.
     *
     * @return An integer indicating the status of the favicon loading process.
     */
    public int favicon_loaded()
    { 
        return _favicon_loaded;
    }


    /**
     * @brief True when the favicon could not be loaded and is not to be shown.
     */
    public bool favicon_failing()
    {
        return _favicon != null && FAILING_FAVICON.contains(_favicon);
    }


    /**
     * @brief Gives a failing favicon a second chance.
     */
    public void favicon_retry()
    {
        if ( _favicon != null )
            FAILING_FAVICON.remove(_favicon);
    }


    /**
     * @brief The file holding the favicon image, or null if there is none.
     */
    public string? favicon_image_file()
    {
        string path = favicon_cache_file();
        return FileUtils.test(path, FileTest.EXISTS) ? path : null;
    }


    /**
     * @brief The presentation layer could not read the cached file: drop it so the next load downloads again.
     */
    public void favicon_unreadable()
    {
        FileUtils.remove(favicon_cache_file());
        image_cache = null;
        _favicon_loaded = 0;
    }

    
    /**
     * @brief Uses the favicon already in the cache, if it may be used.
     *
     * It may be used unless a reload was requested, and even then if the favicon is currently failing.
     *
     * @return true if the favicon was loaded from the cache
     */
    private bool load_favicon_from_cache(bool reload)
    {
        if ( reload && !FAILING_FAVICON.contains(_favicon) )
            return false;
        if ( favicon_image_file() == null )
            return false;

        image_cache = null;
        _favicon_loaded++;
        favicon_sig();
        return true;
    } // load_favicon_from_cache


    /**
     * @brief Reads a stream to the end, giving up past MAX_FAVICON_BYTES.
     */
    private async Bytes? read_limited(InputStream stream) throws Error
    {
        var bytes = new ByteArray();
        while ( true )
        {
            Bytes chunk = yield stream.read_bytes_async(READ_CHUNK_BYTES, Priority.LOW);
            if ( chunk.get_size() == 0 )
                break;
            bytes.append(chunk.get_data());
            if ( bytes.len > MAX_FAVICON_BYTES )
                return null;
        }
        return ByteArray.free_to_bytes((owned) bytes);
    } // read_limited


    /**
     * @brief Downloads the favicon and stores it in the cache.
     *
     * @return true if the favicon was downloaded and is now the station's favicon
     */
    private async bool download_favicon()
    {
        uint status_code;
        InputStream? stream = yield HttpClient.GETasync(_favicon_uri, Priority.LOW, out status_code); // Will automatically try several times

        if ( stream != null && status_code == 200 )
        {
            try {
                Bytes? data = yield read_limited(stream);
                if ( data != null && data.get_size() > 0 )
                {
                    string path = favicon_cache_file();
                    FileUtils.set_data(path, data.get_data());
                    if ( image_check == null || image_check(path) )
                    {
                        image_cache = null;
                        _favicon_loaded++;
                        favicon_sig();
                        return true;
                    }
                    FileUtils.remove(path);
                }
            } catch (Error e) {
                if (Tuner.debug_enabled ())
                    debug(@"$(_favicon) - Failed to process favicon $(_favicon_uri.to_string()) - $(e.message)");
            }
        }
        info(@"$(_favicon) - Failed to load favicon $(_favicon_uri.to_string()) - Status code: $(status_code)");
        return false;
    } // download_favicon


    /**
     * @brief Asynchronously loads the favicon for the station.
     *
     * Loads from cache is not requesting reload and cache exists
     * Otherwise async calls to the website to download the favicon,
     * then stores it in the cache and replaces the Station favicon
     *
     * @param {bool} reload - Whether to force reload the favicon.
     */
    public async void load_favicon_async( bool reload = false )
    {
        if ( _favicon_uri == null || ( !reload && _favicon_loaded > 0 )) return;

        if ( load_favicon_from_cache(reload) )
            return;

        if ( !(yield download_favicon()) )
            FAILING_FAVICON.add(_favicon);
    } // load_favicon_async
} // Favicon
