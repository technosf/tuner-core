/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file MusicBrainzSearch.vala
 *
 * @brief Looking a track up on MusicBrainz.
 */

namespace Tuner.Services
{
	/**
	 * @brief Builds the text to search for a played track, and opens the MusicBrainz search for it.
	 */
	public class MusicBrainzSearch : GLib.Object
	{
		/**
		 * @brief Build the track search text for a title shown by a station.
		 *
		 * Stations often put their own name/id before and/or after the artist and track.
		 * Any such station name at the start or end of the title is removed, together with the
		 * whitespace and punctuation next to it. Falls back to the full title if nothing is left.
		 *
		 * @param raw_title The title the station sent
		 * @param raw_station_name The name of the station
		 * @return The text to search for; empty if the title is empty
		 */
		public static string build_term (string raw_title, string raw_station_name)
		{
			string sep = "[\\s\\p{P}\\p{S}]*";

			var title = raw_title.strip();
			var station_name = raw_station_name.strip();
			if (station_name == "" || title == "")
				return title;

			var cleaned = title;
			try {
				var id = Regex.escape_string(station_name);
				// The id must not be part of a longer word (station "Radio" must not eat "Radiohead").
				var leading  = new Regex("^" + sep + id + "(?![\\p{L}\\p{N}])" + sep, RegexCompileFlags.CASELESS);
				var trailing = new Regex(sep + "(?<![\\p{L}\\p{N}])" + id + sep + "$", RegexCompileFlags.CASELESS);

				// Repeat so "ID - Artist - Title - ID" and doubled ids are all removed.
				string previous = "";
				do {
					previous = cleaned;
					cleaned = leading.replace_literal(cleaned, -1, 0, "");
					cleaned = trailing.replace_literal(cleaned, -1, 0, "");
				} while (cleaned != previous && cleaned != "");
			} catch (RegexError e) {
				warning(@"Unable to clean track search term: $(e.message)");
				return title;
			}

			return cleaned != "" ? cleaned : title;
		} // build_term


		/**
		 * @brief The URL of a MusicBrainz recording search for the term.
		 *
		 * Opening it in the browser is up to the presentation layer.
		 *
		 * @param term The text to search for
		 * @return The search URL, with the term percent-encoded
		 */
		public static string build_url (string term)
		{
			// Percent-encode everything but unreserved characters (spaces become %20).
			var encoded = Uri.escape_string(term, null, false);
			return @"https://musicbrainz.org/search?query=$encoded&type=recording&method=indexed";
		} // build_url
	} // MusicBrainzSearch
}
