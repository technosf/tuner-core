<!--
Copyright © 2026 <https://github.com/technosf>
SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Tuner core contract (draft)

What a presentation layer may rely on from the functional code of Tuner, and what the functional code asks of it.
This is the "functional contract" of `SEPARATION_PLAN.md` (phase P5). It is **derived from the code as it is**
(branch `tng`), not designed ahead of it: where the code does not make a rule clear, the text says *unspecified*
rather than guessing. It grows with the code; the GTK4 prototype (P6) is the test of whether it is enough.

Everything below runs on the GLib main loop of one thread. There are no worker threads; asynchronous methods are
Vala `async` methods that continue on the main loop, so callers need no locking, but must expect that state can
change between a `yield` and its continuation.

## 1. Boundary rules

- Functional code does not use GTK, GDK, Granite or widget types, and does not reference the `Application` class.
  `scripts/check_core_boundary.py` enforces this as a ratchet (see `scripts/core_boundary_baseline.txt`); it runs
  as `meson test` suite `boundary` and in CI.
- Functional code reaches the presentation layer only through `AppContext` (section 2).
- Presentation code reads state through properties and signals, and changes it through the methods listed here.
  It does not hold application state of its own that the functional code also needs.
- Remaining exceptions (see the baseline): `Favicon` and `MprisArtwork` use `Gdk.Pixbuf` (decision D3 in the plan).

## 2. `AppContext` – the application as the functional code sees it

`src/Core/AppContext.vala`. The GTK `Application` implements it today; a core session object will later.

| Member | Type | Meaning |
|---|---|---|
| `events` | `AppEventBus` | the event hub (section 3) |
| `session` | `StationSession` | per-run station state: broken stations, play counts, last played |
| `history` | `History` | the list of what played, with track titles and hearts |
| `player` | `PlayerController` | playback |
| `jukebox` | `JukeboxController` | shuffle mode |
| `connection` | `ConnectionCoordinator` | network and radio-browser connection state |
| `is_online`, `is_offline` | `bool` | the plain network flags |
| `cache_dir` | `string?` | per-user cache folder; null if it could not be created |

Methods the functional code calls on the presentation layer:

| Method | Expected behaviour |
|---|---|
| `play_station_in_ui (Station)` | select the station in the UI and start it. Must do nothing if there is no window yet. Going through the UI (rather than `player.play_station`) lets the UI update its own state (title, selection, last played setting). |
| `present_window ()` | bring the main window to the front, if there is one (MPRIS `Raise`) |
| `choose_starred_stations ()` | show the starred stations. Safe before the window is active; the choice is remembered until it is. |
| `quit_cleanly (reason)` | stop playback, flush the all-time archive, save settings and quit, even when "keep playing" is on |

## 3. Events (`AppEventBus`)

All signals are emitted on the main loop. Payload stations are the shared `Station` objects, not copies.

| Signal | Payload | Meaning |
|---|---|---|
| `connectivity_changed_sig` | `bool is_online` | the plain network flag changed |
| `connection_state_changed_sig` | `ConnectionState` | `OFFLINE`, `CONNECTING` (network up, no server answered yet) or `READY` (network up and a radio-browser server answered). Wait for `READY` before network work. |
| `starred_stations_changed_sig` | `Station` | a station was added to or removed from the starred stations, or flagged while the store loads |
| `station_changed_sig` | `Station` | the current station changed |
| `volume_changed_sig` | `double` (0.0–1.0) | volume changed |
| `playback_time_tick_sig` | `Station`, total seconds, station seconds | every second while a station is playing |
| `tape_counter_sig` | `Station` | a play-time milestone: every 606 seconds (ten minutes plus 1%) of play of one station; pausing stops the count and a station change resets it |
| `shuffle_mode_sig` | `bool` | shuffle mode switched |
| `shuffle_requested_sig` | – | a shuffle step was asked for |
| `player_state_changed_sig` | `Station`, `StreamPlayer.State` | player state changed |
| `playback_metadata_changed_sig` | `Station`, `StreamMetadata` | stream title and related metadata changed |

`StreamPlayer.State`: `BUFFERING`, `PAUSED`, `PLAYING`, `STOPPED`, `STOPPED_ERROR`.
Ordering guarantees between signals (for example `station_changed_sig` before `player_state_changed_sig`) are
*unspecified* in the code today; the presentation must not depend on them.

## 4. Controllers

**`PlayerController`**: `station` (get/set), `player_state`, `volume` (get/set), `play_error`,
`play_error_message`; methods `play_station (Station)`, `can_play ()`, `play_pause ()`, `stop ()`, `shuffle ()`.
Non-playing states are debounced briefly before `player_state_changed_sig` reports them, so a quick
buffering blip does not flicker the UI. Errors set `play_error` and the message until the next successful state.

**`DirectoryController`** (station discovery). Each `load_*` returns a `StationSet`, a pager:
`next_page_async (priority)` returns the next page, or null when there is nothing (throws `SourceError` if the
source is unavailable); `has_more ()` says whether another page exists.

| Method | Returns |
|---|---|
| `load_station_uuid (uuid)`, `get_stations_by_uuid_async (uuids)` | one station / a set by UUID |
| `load_random_stations (limit)`, `load_trending_stations (limit)`, `load_popular_stations (limit)` | `StationSet` |
| `load_by_country (limit, countrycode)`, `load_by_tag (tag)`, `load_search_stations (text, limit)` | `StationSet` |
| `load_random_genres_async (count)` | genre tags |
| `get_starred ()`, `reorder_starred (uuids)` | the starred stations, and their order |
| `add_saved_search (text)`, `remove_saved_search (text)`, `load_saved_searches ()` | saved searches |
| `provider_name ()` | name of the data provider |

**`JukeboxController`**: `enable ()`, `disable ()`, `request_shuffle ()`, `shuffle_to_next_station ()` (async);
signal `shuffle_state_changed_sig (bool)`. It skips stations marked broken in the session, and plays through
`AppContext.play_station_in_ui`.

**`TapeCounterController`**: counts play time per station; signals `playback_time_tick_sig` and `tape_counter_reached_sig`;
`reset ()`.

## 5. Stores and models

- **`StarStore`**: `add_station`, `remove_station`, `contains`, `get_all_stations`, `reorder_stations`,
  `get_all_searches`, saved searches, per-station notes (`has_note`, `get_note`, `set_note`), `export_m3u8 ()`,
  `import_stationuuids (stream)` (throws `IOError`). Changes emit `starred_stations_changed_sig`.
- **`History`**: entries with station, title, hearted flag, played-at, played seconds. Signals `entry_added_sig`,
  `entry_removed_sig`, `entry_changed_sig`, `cleared_sig`. `append`, `clear`, `clear_preserving_last`,
  `build_clipboard_text ()`, hearted-title queries. `HeartedArchive` keeps the all-time hearted list.
- **`StationSession`**: `is_broken`, `mark_broken (station, reason)`, `clear_broken`, `clear_all_broken`,
  `begin_play`, `end_play`, last-played and last-click bookkeeping. Signals `station_marked_broken_sig`,
  `station_recovered_sig`. Not persisted.
- **`Station`**: the radio-browser record: `stationuuid`, `name`, `url`, `homepage`, `tags`, `country`, `language`,
  `codec`, `bitrate`, `votes`, `clickcount`, `favicon`, health fields (`lastcheckok`, `ssl_error`), `starred`, and
  `days_played`. Most are read-only to the presentation. Creating a station starts a favicon load into
  `Paths.cache_dir`. Favicon loading and display are mixed today (see section 1, exception).

## 6. Connection

`ConnectionCoordinator.state` is `OFFLINE`, `CONNECTING` or `READY`, mirrored by `connection_state_changed_sig`.
It retries a failing connection with a growing delay (5, 10, 20 then 30 seconds), replacing the HTTP session after
repeated failures. The presentation shows its offline look until `READY` and must not start network work earlier.

## 7. Settings

`Settings` is a `GLib.Settings` for the application schema. Keys the functional code uses: `auto-play`,
`do-not-vote`, `last-played-station`, `start-on-starred`, `startup-jingle`, `volume`, `play-restart`,
`play-in-background`, `inhibit-sleep`, `save-all-time-hearted`. Keys that belong to the presentation: `theme-mode`,
`language`, `stream-info*` (including `stream-info-image-popup-stay-back`), `category-expanded-mask`, and the window geometry (`pos-x`, `pos-y`, `window-width`,
`window-height`), which `Settings` stores as plain numbers via `remember_window_geometry` and the GTK3 layer reads
and applies (`WindowGeometry`).

## 8. Startup

1. The presentation creates its window and the `AppContext` implementation.
2. The startup jingle plays as soon as the main loop is free (if `startup-jingle`), without waiting for the network.
3. If `start-on-starred`, `choose_starred_stations ()` is called.
4. If `auto-play` and a last station is set, playback waits for the jingle to finish **and** for the connection
   to be `READY`, then calls `play_station_in_ui`.

## 9. Gaps to close (to be settled with the GTK4 prototype)

- Ordering of events, and which events fire on the initial state (the presentation must read state on start).
- Error reporting: playback errors are properties, data errors are exceptions and `last_data_error`; there is no
  single error channel.
- Object lifetime: who owns `Station` objects, and how long a `StationSet` stays valid.
- A list-model view of stations for toolkits that want one (decision D4).
- The `AppContext` services move into a core session object (plan phase P2); the interface stays as the
  presentation's view of it.
