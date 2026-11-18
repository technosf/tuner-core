/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020-2022 Louis Brauer <louis@brauer.family>
 */

using Gee;

namespace Tuner.Models.Genre {

    private static Set<string> PREDEFINED;

    /**
     * @brief Whether a tag is one of the predefined genres or subgenres.
     */
    public static bool in_genre(string genre)
    {
        if ( PREDEFINED == null)
        {
            PREDEFINED = new HashSet<string>();
            foreach( var a in GENRES) {PREDEFINED.add(a); }
            foreach( var a in SUBGENRES) {PREDEFINED.add(a); }
            foreach( var a in ERAS) {PREDEFINED.add(a); }
            foreach( var a in eras ()) {PREDEFINED.add(a); }
            foreach( var a in TALK) {PREDEFINED.add(a); }
        }
        return PREDEFINED.contains(genre);
    }

    public  const string[] GENRES = {
        "Blues",
        "Classical",
        "Country",
        "Dance",
        "Disco",
        "Easy",
        "Folk",
        "Hits",
        "Jazz",
        "Oldies",
        "Pop",
        "Rap",
        "Rock",
        "Soul"
        };   

    public  const string[] SUBGENRES = {
        "Alternative",
        "Ambient", 
        "Club", 
        "Electronic", 
        "Funk",
        "HipHop",
        "House",
        "Indie",
        "Metal",
        "Latino",
        "Punk",
        "Reggae",
        "Salsa",
        "World Music"
    };     
        
    /**
     * @brief The eras, built from the calendar: each decade from the 1940s up to, but not including, the current
     * decade, then Contemporary.
     *
     * The tags follow the directory's: "40s" to "90s", then "2000s", "2010s" and so on. In the 2020s that is
     * "40s" ... "2010s", "Contemporary"; in the 2030s "2020s" joins them.
     */
    public static string[] eras ()
    {
        int this_decade = (new DateTime.now_local ().get_year () / 10) * 10;

        string[] list = {};
        for (int decade = 1940; decade < this_decade; decade += 10)
            list += (decade < 2000) ? "%ds".printf (decade % 100) : "%ds".printf (decade);
        list += "Contemporary";
        return list;
    } // eras


    /** @brief The eras as they stood when this list was written; see eras () for the ones that follow the calendar */
    public  const string[] ERAS = {
        "40s",
        "50s",
        "60s",
        "70s",
        "80s",
        "90s",
        "2000s",
        "2010s",
        "Contemporary"
    };         
        
    public  const string[] TALK = 
    {   "AM"
        ,"Comedy"
        ,"College Radio"
        ,"Community Radio"
        ,"Culture"
        ,"Educational"
        ,"Kids"
        ,"Public Radio"
        ,"News"
        ,"Religion"
        ,"Sport"
        ,"Talk"
    };               
}




