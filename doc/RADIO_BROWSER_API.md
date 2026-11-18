<!--
SPDX-License-Identifier: GPL-3.0-or-later
-->
# radio-browser.info API: how Tuner uses it, and where it could use it better

Reviewed 2026-11-11. Code: `src/Providers/RadioBrowser.vala`, `RadioBrowserServers.vala`, `src/Controllers/DirectoryController.vala`,
`src/Services/HttpClient.vala`, `src/Models/Station.vala`.

## 1. What "7.5" is, and what is verified

The server software (`radiobrowser-api-rust`, now hosted on GitLab: `gitlab.com/radiobrowser/radiobrowser-api-rust`) is at
**0.7.50, tagged 2026-11-11** (0.7.49 the same day, 0.7.48 on 10 Nov, 0.7.47 on 8 Nov, 0.7.46 on 11 Oct, 0.7.45 on 21 Aug,
0.7.44 on 7 Mar, 0.7.43 on 5 Feb, 0.7.42 on 18 Jan 2026). I take "7.5" to mean 0.7.50. The API is the same `/json/...` wire
API as before.

**Not verified: the release notes for 0.7.25 to 0.7.50.** The GitLab changelog and release pages could not be read from the
environment this was written in (script-rendered pages, robots rules and a blocked git host). So this document is checked against:
the API reference at docs.radio-browser.info, the 0.7.0 to 0.7.24 changelog (GitHub mirror, last commit 2023), and our code.
Anything new in 0.7.25+ that is not in the reference is not covered. **To do:** read `CHANGELOG.md` / Releases at the GitLab
project for 0.7.25 to 0.7.50 and add anything API-visible to section 5. Also read the live `software_version` from
`https://de2.api.radio-browser.info/json/stats` (the app logs it in debug and shows it in About's provider text).

Changes in the last known changelog (0.7.5 to 0.7.24) that touch us:

| Version | Change | Effect on Tuner |
|---|---|---|
| 0.7.5 | Do-not-index streams are deleted; `url` is overridden when a stream override is set | none; stations just disappear from the index (we handle "no longer in the index") |
| 0.7.15 | Search by `has_extended_info` and `is_https`; `iso_3166_2` in station lists | unused (see 4.3) |
| 0.7.17 | `changetimestamp` order | unused |
| 0.7.18 to 0.7.21 | Streaming-server tables, favicon checks (empty favicons are looked up on the website; missing ones removed daily), language codes | fewer broken favicons; `languagecodes` read, not shown |
| 0.7.23 | Countries endpoint gains `countrycode`; **`/countrycodes` deprecated**; uppercase uuids accepted | we use neither endpoint |
| 0.7.24 | Station check refreshes all fields | none |

## 2. The API as Tuner uses it today

Base: `https://<server>/json/...`, HTTPS only, JSON only. User-Agent is `<app id>/<app version>`
(`Tuner.user_agent()`), set on the libsoup session (API calls) and on the GStreamer HTTP source (streams).

### 2.1 Server discovery and choice

| Step | Call | Notes |
|---|---|---|
| Find servers | DNS SRV `_api._tcp.radio-browser.info` | as the docs recommend |
| Fallback | `GET all.api.radio-browser.info/json/servers` | only when SRV gives nothing |
| Reserve | `de2.api.radio-browser.info` | used when fewer than two servers are known |
| Choose | `GET /json/stats` on 3 candidates, fastest wins | `ServerSelector`; the winner's stats response is kept, not asked for again |
| Health | each query result scores the server; failures degrade it, a bad run retires it for a cool-down and a new choice is made | `degrade()` / `retire_current_server()` |
| Retry | up to 3 attempts per catalogue query; a retryable failure (no response or 5xx) moves to the next server; 300 ms x attempt pause | 4xx is not retried |

Every request carries a `nocache=<ms>` cache-busting parameter (unknown parameters are ignored by the server). The query gate
(`WorkGate`) holds all queries until a server is chosen.

### 2.2 Endpoints called

| Endpoint | Where | Parameters we send |
|---|---|---|
| `GET /json/stats` | start-up probe, `read_stats` | none. We read `stations`, `tags`, `supported_version`, `software_version`; they feed the About text and the header tooltip ("N stations, N tags") |
| `GET /json/stations/search` | every list: Discover (random), Trending, Popular, by country, by tag, text search | `limit`, `offset`, `order`, `reverse` (not for random), `hidebroken=true`, optional `name` (percent-encoded), `countrycode`, `tagList` (comma separated) with `tagExact=false` |
| `GET /json/stations/byuuid` | Starred sync, a station by uuid | `uuids=<comma list>` |
| `GET /json/tags` | Explore tags | `offset`, `limit` (a 1000-tag window at a random offset, 3 attempts, 5 shown) |
| `GET /json/url/<stationuuid>` | click, each time a station starts playing that was not the last one played this session (background, low priority, fire and forget; no local 24-hour check, the directory ignores repeats) | none. The response is ignored; we play `url_resolved`, falling back to `url` |
| `GET /json/vote/<stationuuid>` | when a station is starred (background) | none |

How the app's lists map onto `/stations/search`:

| List | `order` | Notes |
|---|---|---|
| Stations to Discover | `random` | the set re-asks with a rising offset |
| Trending | `clickcount` | clicks in the last 24 h. `clicktrend` was checked live (Oct 2026) and equals `clickcount` for every station, so it is not used |
| Popular | `votes` | votes are never reset |
| Country | `clickcount` + `countrycode` | |
| Tag | `votes` + `tagList` | |
| Search | `clickcount` + `name` | |

Page size is 41 (`DIRECTORY_LIMIT`); the pager asks for one more than it shows to know whether there is a next page.

### 2.3 Station fields read

`changeuuid, stationuuid, name, url, url_resolved, homepage, favicon, tags, country, countrycode, state, language,
languagecodes, votes, lastchangetime, codec, bitrate, hls, lastcheckok, lastchecktime, lastcheckoktime, lastlocalchecktime,
clicktimestamp, clickcount, clicktrend, ssl_error, geo_lat, geo_long, has_extended_info`. Missing or null strings read as "".
Legacy `id`, `location`, `title` are accepted when a station comes from an older local file, not from the API.

Shown in the UI: name, favicon, tags, country/state, language, codec + bitrate, votes/popularity, homepage. The rest is held
for the station-change comparison ("Station info updated Online - View changes"), not displayed.

### 2.4 Rules of the API we follow

Speaking User-Agent; random server order and retry on the next; uuids and `countrycode` rather than `id`/`country`; `hidebroken=true`;
click on every play; HTTPS; no hard-coded single server (one reserve host only as a last resort).

### 2.5 Not used at all

The `/stations/by...` variants, `topclick`, `topvote`, `lastclick`, `lastchange`, `changed`, `broken`, `/countries`,
`/countrycodes`, `/states`, `/languages`, `/codecs`, `/clicks`, `/checks`, `/checksteps`, `/config`, `/add`, `/stations/byurl`,
`/metrics`, other output formats (xml, csv, m3u, pls, xspf), POST parameters.

## 3. Things worth tidying in what we already do

1. **Votes** are sent each time the user stars a station (`station_starred_sig`, not when starred stations load or are imported). The API accepts
   one vote per IP per station every 10 minutes, so star, unstar and star again inside that time is counted once. The Preferences option
   "do not vote" turns votes and clicks off.
2. **Clicks.** The docs say to send one "every time a user starts playing a stream"; the same IP and station counts once per day, extra
   calls are ignored. We send one whenever a station starts playing that was not the last station played in the session. Resuming the same
   station does not click; going to another and back does.
3. **`/json/stats` figures are read once.** The header tooltip does not refresh after a later server change.
4. **Countries and languages are static lists** (`Models/Countries.vala`, `Languages.vala`). New or renamed countries need an
   app update (see 4.2).
5. **Wire-version check.** `RBI_API_SUPPORTED_VERSION = 1` only warns. Good enough; keep.
6. **Cache buster** is added to every request except clicks (`/json/url`) and votes (`/json/vote`), which are now sent bare, as the directory asks. Right for random picks; for `/json/tags`, `/stats` and `/servers` it
   defeats legitimate caching and costs the volunteer servers more. Consider dropping it for those.
7. **`hidebroken=true`** hides stations whose last check failed, even briefly. Fine for Discover; Starred stations are fetched by
   uuid, which does not use it, so they are never hidden.

## 4. Where we could use the API better, or more fully

Ordered by value for the product.

### 4.1 Cheap and valuable

- **More Discover lists.** `/stations/topclick`, `/topvote` (rowcount in the path) are the server's own ranked lists, and
  `/stations/lastclick` ("what others are listening to right now") is a genuinely different list we do not have. Candidate new
  entry: **Playing now**. `/stations/lastchange` gives "New and updated stations".
- **Server's view of a broken stream.** `StationSession` marks stations broken for the session from our own errors. The API has no
  "report broken" call, but `GET /json/checks/<stationuuid>` shows the server's own recent checks; a details view could say
  "the directory also sees this stream failing".
- **Batch Starred sync.** `byuuid` takes a list; keep batching, and cap the list (about 40 uuids a call) or send it as a POST body.
- **`is_https`.** `/stations/search?is_https=true` (0.7.15) avoids certificate failures (`ssl_error`) on playback. Offer
  "Secure streams only" as a preference.
- **Bitrate and codec filters.** `bitrateMin`/`bitrateMax`, `order=bitrate`, `codec=` for "good quality only", "low data", or
  avoiding formats a user's GStreamer install lacks.

### 4.2 Replace the static lists with the live ones

- **`/json/countries`** (now with `countrycode`) instead of `Countries.vala`: also gives `stationcount`, so the country list can hide
  empty countries and show counts. Avoid `/countrycodes` (deprecated).
- **`/json/languages`** (ISO 639 codes since 0.7.20) for a language filter; `languagecodes` is already on every station.
- **`/json/states?country=`** to browse by region; `iso_3166_2` on stations identifies subdivisions.
- **`/json/tags?order=stationcount&reverse=true&hidebroken=true`** for a "top tags" Explore, besides the random tags. Today we
  fetch a random 1000-tag window by offset; sorted by `stationcount` is one cheaper call and avoids tags with one station.
- Cache these on disk with a date and refresh weekly; they change slowly.

### 4.3 New search facets (advanced `stations/search`)

Used: `name`, `countrycode`, `tagList`. Not used: `language`, `state`, `codec`, `bitrateMin/Max`, `has_geo_info`,
`has_extended_info`, `is_https`, the `...Exact` variants, `order=lastchecktime|clicktimestamp|changetimestamp`. Together these make
an **advanced search** panel possible with no new endpoint. `has_geo_info` plus `geo_lat`/`geo_long` (already read, unused) could
later drive "stations near me / on a map".

### 4.4 Being a better API citizen

- Keep the **speaking User-Agent**. It now reads `<app id>/<app version> (pkg: <packaging>; os: <distro id>) tuner-core/<core version>`, built by `Tuner.UserAgent` in `Utils.vala`. The packaging comes from the frontend meson option `-Dpackaging=<deb|rpm|aur|nix|flatpak|snap|appimage|...>`, or is detected at run time (flatpak, snap, appimage), else "source". (Before this change it reported the *core* version as the app version.) Consider a project URL too.
- Allow normal HTTP caching for `/stats`, `/tags`, `/countries` (see 3.6).
- Keep SRV discovery; make the reserve host a short list.
- Servers are run by volunteers: keep the retry and cool-down limits as they are.

### 4.5 Contributing back (optional, later)

- **`/json/add`** (`name` up to 400 chars, `url`, homepage, favicon, two-letter `countrycode`, state, language, tags, geo): an
  "Add a station to the directory" action. Public and moderated, so it needs a proper form.
- Click and vote hygiene (3.1, 3.2) keeps our traffic from skewing the directory.

### 4.6 Other output formats

`m3u`, `pls`, `xspf` output could let Share hand out a playlist for one station. Low priority; the stream address plus QR is enough.

## 5. Open questions for the 0.7.25 to 0.7.50 changes (fill in)

Check each against the GitLab changelog; any "yes" needs a core change and a test:

- [ ] New or renamed fields on the station object (are any members we read as int now strings or null?)
- [ ] `clicktrend` fixed (we avoid it because it equals `clickcount`)? If so, Trending could use it again.
- [ ] Server discovery changed (SRV, `/json/servers`, new domain, HTTPS-only)?
- [ ] New or removed `order` values; does `random` still ignore `reverse`?
- [ ] Any rate limit, API key or User-Agent policy now enforced?
- [ ] `countrycodes` removed (unused by us); `countries` changes (planned use in 4.2)
- [ ] New `stats` fields (is `supported_version` still 1?)
- [ ] Anything about `hidebroken` or broken-station handling

## 6. Suggested order of work

1. Read the 0.7.25 to 0.7.50 notes; tick section 5; run the app once and note the logged `software_version`.
2. 3.6 (cache buster only where it matters). Small and safe.
3. 4.1 (`topclick`/`lastclick`, `is_https`, bitrate/codec preferences).
4. 4.2 (live countries/languages with station counts, cached).
5. 4.3 (advanced search panel); 4.5 only if there is demand.

## Sources

- API reference: https://docs.radio-browser.info/ and https://api.radio-browser.info/
- Server changelog to 0.7.24 (GitHub mirror): https://github.com/segler-alex/radiobrowser-api-rust/blob/master/CHANGELOG.md
- Current server project (tags to 0.7.50): https://gitlab.com/radiobrowser/radiobrowser-api-rust/-/tags
