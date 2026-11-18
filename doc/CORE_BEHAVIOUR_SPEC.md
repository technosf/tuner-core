# Tuner core: behaviour specification

What the functional core promises to any presentation layer. Each scenario has an id, is stated as given / when / then,
and names the test that proves it (`tests/core-tests.vala`) or says **untested**. Status: **required** (every
frontend can rely on it), or **optional** (a frontend may ignore it).

This is a draft written from the tests and `CORE_CONTRACT.md`. It grows with the tests (SEPARATION_PLAN.md, P4/P5).
The API each scenario uses is in `CORE_CONTRACT.md`; events are in `EVENTS_ARCHITECTURE.md`.

## 1. Start-up

| Id | Scenario | Test | Status |
|---|---|---|---|
| S1 | **Given** a host, **when** a frontend creates `CoreSession(host, app_id)`, **then** every service exists and nothing is shown or played. | `/session/builds` | required |
| S2 | **When** `start_services()` is called, **then** the directory connection and MPRIS start; calling it again does nothing. | untested | required |
| S3 | **When** `start()` is called, **then** services are started if needed, the starred stations and saved searches load once the connection is first ready, and the start-up flows run (sound if the host gives one, start on starred, auto-play). | `/startup/starred`, `/startup/autoplay` | required |
| S4 | **Given** auto-play is on and a last station is saved, **when** the connection is ready and any start-up sound has finished, **then** that station is played once per session through `Host.play_station_in_ui`. | `/startup/autoplay`, `/startup/autoplay-off` | optional |

## 2. Playback

| Id | Scenario | Test | Status |
|---|---|---|---|
| P1 | **When** `play_station(s)` is called, **then** `station_changed_sig` is emitted at once and the stream starts shortly after (about half a second, to let metadata arrive). | `/player/plays-a-station` | required |
| P2 | **When** the stream reports it is playing and the network is up, **then** `player_state` is PLAYING and `player_state_changed_sig` carries PLAYING. | `/player/plays-a-station` | required |
| P3 | **Given** the network is down, **when** a station is played, **then** the stream is stopped and the state stays STOPPED. | `/player/offline` | required |
| P4 | **When** `play_pause()` is called while playing, **then** the stream stops and the state becomes STOPPED; called again, it plays. | `/player/play-pause` | required |
| P5 | **When** a station is played while another plays, **then** the first crossfades to the second. | `/player/crossfade` | required |
| P6 | **When** the stream fails, **then** the first error message is kept (`play_error`, `play_error_message`) and later errors from the same failure are ignored; with a network, the station is marked broken for the session. The next `play_station` clears the error. | `/player/failure` | required |
| P7 | **When** the volume is set, **then** `volume_changed_sig` is emitted, the setting is saved and the volume reads back. | `/player/volume` | required |
| P8 | **When** the state flips between playing and buffering for under a second, **then** the change is held back (debounced) and not announced. | `/player/buffering-blip`, `/player/buffering-lasts` | required |

## 3. Directory, search and starred stations

| Id | Scenario | Test | Status |
|---|---|---|---|
| D1 | **When** a station is starred, **then** it is in the store, `starred_stations_changed_sig` is emitted once, and starring it again does nothing. | `/stars/add-remove` | required |
| D2 | **When** a station is unstarred, **then** it leaves the store, its note is dropped and the change is announced. | `/stars/add-remove`, `/stars/notes` | required |
| D3 | **When** the starred order is set, **then** the listed stations come first in that order and any left out follow. | `/stars/order` | required |
| D4 | A note is kept only for a starred station, is trimmed, is removed when blank and is cut at 500 characters. | `/stars/notes` | required |
| D5 | Saved searches form a set: no duplicates; removal works. | `/stars/saved-searches` | required |
| D6 | **When** the app restarts, **then** starred stations, their order, notes and saved searches come back from the file. | `/stars/survive-restart` | required |
| D7 | **When** a station set is asked for its next page while offline, **then** it returns null. | `/directory/offline-page` | required |
| D8 | **When** the directory fails, **then** a station set raises `SourceError.UNAVAILABLE`. | untested | required |
| D9 | **When** a page comes back empty (the real provider answers a failed request with an empty set), **then** the station set does not move on, so asking again requests the same offset. | `/directory/empty-page-retry` | required |

## 4. History and hearts

| Id | Scenario | Test | Status |
|---|---|---|---|
| H1 | Appending the same station and title twice adds one entry. | `/history/append` | required |
| H2 | An entry with no title is replaced when a title arrives for the same station. | `/history/titleless-replaced` | required |
| H3 | Station changes, distinct tracks, hearted tracks and played seconds are counted from the entries. | `/history/counts`, `/history/hearts`, `/history/play-time` | required |
| H4 | Time counts only while the entry is playing and only for the active station. | `/history/play-time` | required |
| H5 | Hearting applies to the current entry when station and title match; hearted titles are listed in play order. | `/history/hearts` | required |
| H6 | Clearing removes every entry; clearing but keeping the last keeps the current one. | `/history/clear` | required |
| H7 | The clipboard text lists entries newest first with hearts marked. | `/history/clipboard-text` | optional |

## 5. Connection and network

| Id | Scenario | Test | Status |
|---|---|---|---|
| N1 | **When** the network goes away, **then** `changed(false)` is emitted and the cancellable is cancelled so requests end at once; when it returns the cancellable is reset. A repeat report changes nothing. | `/network/state-changes` | required |
| N2 | A server that fails often enough (8 samples) is retired for five minutes; a healthy server is preferred; a cooling server ranks last. | `/pool/*` | required |
| N3 | Queries wait at the work gate while a server is being chosen and go ahead when it opens. | `/gate/*` | required |
| N4 | The connection state is OFFLINE without a network, CONNECTING when the network is up and no server has answered, and READY once one has. | `/connection/ready`, `/connection/offline`, `/connection/proven`, `/connection/no-answer` | required |
| N5 | **When** playback was running and the network drops and returns, **then** playback restarts if the user's setting says so, and does not if the setting is off or the user had stopped it. | `/recovery/restarts`, `/recovery/restart-off`, `/recovery/user-stopped` | optional |

## 6. Station session

| Id | Scenario | Test | Status |
|---|---|---|---|
| X1 | Marking a station broken is announced once; a second mark counts an error but is not announced; clearing is announced once. | `/session/broken-and-recovered` | required |
| X2 | Clearing all broken stations empties the list. | `/session/clear-all` | required |

## Known mismatches (to settle in the spec)

- Reloading the starred file reads member names the saved file does not always use; Json criticals are silenced in
  `Station.basic`.
- `StarStore.persist()` needs the file to exist (`load()` creates it); starring before `load()` loses the save.
- A failure marks a station broken only when the machine reports a network (`/player/no-network-no-blame`). The player controller takes the machine's answer through `PlayerController.NetworkProbe`, so tests no longer depend on the machine they run on.
- `RadioBrowser.search_async` is documented to throw `DataError` when it cannot get the stations, but a failed request
  (after its retries) returns an empty set, the same as a search that found nothing. So `D8` (`SourceError`) rarely
  happens in practice, and a frontend cannot tell a failure from an empty result. A frontend can tell one case: an
  empty page after a page that said there was more. The core should throw instead (decision for the spec).
