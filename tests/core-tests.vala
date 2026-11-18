/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file core-tests.vala
 *
 * @brief Headless tests of the functional core. They need no display, no network and no GTK.
 */

using Gee;
using Tuner.Controllers;
using Tuner.Coordinators;
using Tuner.Events;
using Tuner.Models;
using Tuner.Services;
using Tuner.Services.DataProvider;

// ----------------------------------------------------------
// Helpers
// ----------------------------------------------------------

/** A station built from the same JSON the directory sends, with every member Station.basic reads. */
Station make_station (string uuid, string name)
{
    var b = new Json.Builder ();
    b.begin_object ();
    string[] text = {
        "changeuuid", "url", "url_resolved", "homepage", "favicon", "tags", "country", "countrycode",
        "iso_3166_2", "state", "language", "languagecodes", "lastchangetime", "lastchangetime_iso8601",
        "codec", "lastchecktime", "lastchecktime_iso8601", "lastcheckoktime", "lastcheckoktime_iso8601",
        "lastlocalchecktime", "lastlocalchecktime_iso8601", "clicktimestamp", "clicktimestamp_iso8601",
        "geo_lat", "geo_long", "urlResolved"
    };
    foreach (var key in text)
        b.set_member_name (key).add_string_value ("");
    b.set_member_name ("stationuuid").add_string_value (uuid);
    b.set_member_name ("name").add_string_value (name);
    string[] numbers = { "votes", "bitrate", "hls", "lastcheckok", "clickcount", "clicktrend", "ssl_error" };
    foreach (var key in numbers)
        b.set_member_name (key).add_int_value (0);
    b.set_member_name ("has_extended_info").add_boolean_value (false);
    b.end_object ();
    return new Station.basic (b.get_root ());
}

/** Let the main loop run everything that is ready. */
void wait_for ()
{
    var ctx = MainContext.default ();
    while (ctx.pending ())
        ctx.iteration (false);
}


/** A check that is kept in every build type (assert can be compiled out). */
void check (bool condition, string what)
{
    if (!condition)
    {
        Test.message ("FAILED: %s", what);
        Test.fail ();
    }
}


// ----------------------------------------------------------
// ServerPool
// ----------------------------------------------------------

ServerPool make_pool (string[] names)
{
    var pool = new ServerPool ();
    var list = new ArrayList<string> ();
    foreach (var n in names)
        list.add (n);
    pool.set_servers (list);
    return pool;
}

void test_pool_membership ()
{
    var pool = make_pool ({ "a", "b" });
    check (pool.size == 2, "pool.size == 2");
    check (pool.contains ("a"), "pool.contains (\"a\")");
    check (!pool.contains ("z"), "!pool.contains (\"z\")");

    var more = new ArrayList<string> ();
    more.add ("b");
    more.add ("c");
    assert (pool.add_servers (more) == 1);        // only "c" is new
    check (pool.size == 3, "pool.size == 3");
}

void test_pool_unknown_server_is_ignored ()
{
    var pool = make_pool ({ "a" });
    check (!pool.record ("nope", false), "!pool.record (\"nope\", false)");
    check (!pool.is_cooling ("nope"), "!pool.is_cooling (\"nope\")");
}

void test_pool_retires_after_enough_failures ()
{
    var pool = make_pool ({ "a" });

    // A server is not judged before it has been tried enough times
    for (int i = 0; i < 7; i++)
        check (!pool.record ("a", false), "!pool.record (\"a\", false)");

    assert (pool.record ("a", false));             // the 8th failure: retire it
    pool.retire ("a");
    check (pool.is_cooling ("a"), "pool.is_cooling (\"a\")");
    assert (pool.best () == null);                 // the only server is cooling
}

void test_pool_prefers_the_healthy_server ()
{
    var pool = make_pool ({ "bad", "good" });
    for (int i = 0; i < 5; i++)
    {
        pool.record ("bad", false);
        pool.record ("good", true, 50.0);
    }
    check (pool.ranked ()[0] == "good", "pool.ranked ()[0] == \"good\"");
    check (pool.best () == "good", "pool.best () == \"good\"");
    assert (pool.best ("good") == "bad");          // excluding the best gives the next
}

void test_pool_cooling_server_ranks_last ()
{
    var pool = make_pool ({ "a", "b" });
    pool.retire ("a");
    check (pool.ranked ()[0] == "b", "pool.ranked ()[0] == \"b\"");
    check (pool.best () == "b", "pool.best () == \"b\"");
}


// ----------------------------------------------------------
// NetworkState
// ----------------------------------------------------------

void test_network_state_changes ()
{
    var net = new NetworkState ();
    int changes = 0;
    bool last = false;
    net.changed.connect ((online) => { changes++; last = online; });

    check (net.is_offline, "net.is_offline");

    net.set_online (true);
    check (net.is_online, "net.is_online");
    check (changes == 1 && last, "changes == 1 && last");
    check (!net.cancellable.is_cancelled (), "!net.cancellable.is_cancelled ()");

    net.set_online (true);                         // no change, no signal
    check (changes == 1, "changes == 1");

    net.set_online (false);
    check (net.is_offline, "net.is_offline");
    check (changes == 2 && !last, "changes == 2 && !last");
    assert (net.cancellable.is_cancelled ());      // requests in flight are ended

    net.set_online (true);
    assert (!net.cancellable.is_cancelled ());     // and the next ones can run
}


// ----------------------------------------------------------
// WorkGate
// ----------------------------------------------------------

void test_work_gate_waits_until_open ()
{
    var gate = new WorkGate ();
    bool released = false;

    gate.close ();
    check (gate.closed, "gate.closed");
    gate.wait_until_open.begin ((obj, res) =>
    {
        gate.wait_until_open.end (res);
        released = true;
    });

    wait_for ();
    assert (!released);                            // still closed

    gate.open ();
    wait_for ();
    check (released, "released");
    check (!gate.closed, "!gate.closed");
}

void test_work_gate_open_does_not_wait ()
{
    var gate = new WorkGate ();
    bool released = false;
    gate.wait_until_open.begin ((obj, res) =>
    {
        gate.wait_until_open.end (res);
        released = true;
    });
    wait_for ();
    check (released, "released");
}


// ----------------------------------------------------------
// StationSession
// ----------------------------------------------------------

void test_session_broken_and_recovered ()
{
    var session = new StationSession ();
    var station = make_station ("uuid-1", "One");
    int broken_signals = 0;
    int recovered_signals = 0;
    session.station_marked_broken_sig.connect ((s, reason) => { broken_signals++; });
    session.station_recovered_sig.connect ((s) => { recovered_signals++; });

    check (!session.is_broken (station), "!session.is_broken (station)");
    check (session.lookup (station) == null, "session.lookup (station) == null");

    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*marked broken*");
    check (session.mark_broken (station, "403"), "session.mark_broken (station, \"403\")");
    Test.assert_expected_messages ();
    check (session.is_broken (station), "session.is_broken (station)");
    check (session.broken_count == 1, "session.broken_count == 1");
    check (broken_signals == 1, "broken_signals == 1");

    assert (!session.mark_broken (station, "403 again"));   // already broken: not newly marked
    check (session.lookup (station).error_count == 2, "session.lookup (station).error_count == 2");
    check (broken_signals == 1, "broken_signals == 1");

    session.clear_broken (station);
    check (!session.is_broken (station), "!session.is_broken (station)");
    check (session.broken_count == 0, "session.broken_count == 0");
    check (recovered_signals == 1, "recovered_signals == 1");

    session.clear_broken (station);                // clearing again does nothing
    check (recovered_signals == 1, "recovered_signals == 1");
}

void test_session_clear_all ()
{
    var session = new StationSession ();
    var one = make_station ("uuid-1", "One");
    var two = make_station ("uuid-2", "Two");

    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*marked broken*");
    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*marked broken*");
    session.mark_broken (one, "x");
    session.mark_broken (two, "y");
    Test.assert_expected_messages ();
    check (session.broken_count == 2, "session.broken_count == 2");

    session.clear_all_broken ();
    check (session.broken_count == 0, "session.broken_count == 0");
    check (!session.is_broken (one) && !session.is_broken (two), "!session.is_broken (one) && !session.is_broken (two)");
}


// ----------------------------------------------------------
// History
// ----------------------------------------------------------

void test_history_append_and_duplicates ()
{
    var history = new History ();
    var one = make_station ("uuid-1", "One");
    int added = 0;
    history.entry_added_sig.connect ((e) => { added++; });

    history.append (one, "Song A");
    history.append (one, "Song A");               // same station and title: ignored
    check (history.entries.size == 1, "duplicate ignored");
    check (added == 1, "one entry_added signal");
    check (history.last_entry.title == "Song A", "last entry is Song A");

    history.append (one, "Song B");
    check (history.entries.size == 2, "new title adds an entry");
    check (history.last_entry.title == "Song B", "last entry is Song B");
}

void test_history_titleless_entry_is_replaced ()
{
    var history = new History ();
    var one = make_station ("uuid-1", "One");
    int removed = 0;
    history.entry_removed_sig.connect ((e) => { removed++; });

    history.append (one, "");                      // station started, no title yet
    history.append (one, "Song A");                // title arrives: replaces the empty entry
    check (history.entries.size == 1, "empty entry replaced");
    check (removed == 1, "replaced entry reported removed");
    check (history.last_entry.title == "Song A", "titled entry kept");
}

void test_history_counts ()
{
    var history = new History ();
    var one = make_station ("uuid-1", "One");
    var two = make_station ("uuid-2", "Two");

    history.append (one, "A");
    history.append (one, "B");
    history.append (two, "A");
    history.append (one, "A");
    check (history.station_change_count == 3, "one, two, one is three runs");
    check (history.distinct_track_count == 3, "A and B on one, A on two");
}

void test_history_hearts ()
{
    var history = new History ();
    var one = make_station ("uuid-1", "One");
    var two = make_station ("uuid-2", "Two");

    history.append (one, "A");
    check (!history.is_last_entry_hearted_for (one, "A"), "not hearted yet");
    check (!history.set_last_entry_hearted_if_matches (two, "A", true), "other station does not match");
    check (!history.set_last_entry_hearted_if_matches (one, "B", true), "other title does not match");
    check (history.set_last_entry_hearted_if_matches (one, "A", true), "match hearts it");
    check (history.is_last_entry_hearted_for (one, "A"), "now hearted");
    check (history.hearted_track_count == 1, "one hearted track");

    history.append (one, "B");
    var titles = history.get_hearted_titles ();
    check (titles.size == 1 && titles[0] == "A", "hearted titles are [A]");
    var lines = history.get_hearted_history_lines ();
    check (lines.size == 1 && lines[0] == "One: A", "hearted line is 'One: A'");
}

void test_history_play_time ()
{
    var history = new History ();
    var one = make_station ("uuid-1", "One");
    history.append (one, "A");

    history.tick_playback (one, 5);                // not playing yet: ignored
    check (history.total_played_seconds == 0, "no time before playing");

    history.sync_play_state (one, StreamPlayer.State.PLAYING);
    history.tick_playback (one, 5);
    history.tick_playback (one, 3);
    check (history.total_played_seconds == 8, "8 seconds while playing");

    history.sync_play_state (one, StreamPlayer.State.PAUSED);
    history.tick_playback (one, 5);                // paused: ignored
    check (history.total_played_seconds == 8, "no time while paused");

    var two = make_station ("uuid-2", "Two");
    history.sync_play_state (two, StreamPlayer.State.PLAYING);   // other station: ignored
    check (!history.last_entry.playing, "other station's state ignored");
}

void test_history_clear ()
{
    var history = new History ();
    var one = make_station ("uuid-1", "One");
    int removed = 0;
    int cleared = 0;
    history.entry_removed_sig.connect ((e) => { removed++; });
    history.cleared_sig.connect (() => { cleared++; });

    history.append (one, "A");
    history.append (one, "B");
    history.append (one, "C");

    history.clear_preserving_last ();
    check (history.entries.size == 1 && history.last_entry.title == "C", "only the current entry stays");
    check (removed == 2, "two entries reported removed");

    history.clear ();
    check (history.entries.size == 0 && history.last_entry == null, "empty after clear");
    check (cleared == 1, "cleared signal once");
}

void test_history_clipboard_text ()
{
    var history = new History ();
    var one = make_station ("uuid-1", "One");
    history.append (one, "A");
    history.append (one, "B");
    history.set_last_entry_hearted_if_matches (one, "B", true);
    check (history.build_clipboard_text () == "One\n\t♥ B\nOne\n\tA\n", "newest first, hearts marked");
}


// ----------------------------------------------------------
// StarStore
// ----------------------------------------------------------

/** A directory provider that answers nothing: enough for code that only needs one to exist. */
class FakeProvider : Object, API
{
    public DataError? last_data_error { get; protected set; }
    public API.Status status { get; protected set; default = API.Status.OK; }
    public string name () { return "fake"; }
    public int available_stations () { return 0; }
    public int available_tags () { return 0; }
    public async bool initialize_async () { return true; }
    public void click (string stationuuid) {}
    public void vote (string stationuuid) {}
    public async Set<Tag> get_tags_async (int offset = 0, int limit = 0) throws DataError
    {
        return new HashSet<Tag> ();
    }
    public async Set<Station> by_uuids_async (Collection<string> uuids) throws DataError
    {
        return new HashSet<Station> ();
    }
    public async Set<Station> search_async (SearchParams params, uint rowcount, uint offset = 0,
                                            int priority = GLib.Priority.HIGH_IDLE) throws DataError
    {
        return new HashSet<Station> ();
    }
}

/**
 * A provider that answers the first search with nothing, as the real one does when a request fails, then with
 * three stations, and notes the offset of each search.
 */
class PagingProvider : Object, API
{
    public DataError? last_data_error { get; protected set; }
    public API.Status status { get; protected set; default = API.Status.OK; }
    public Gee.ArrayList<uint> offsets = new Gee.ArrayList<uint> ();
    public string name () { return "paging"; }
    public int available_stations () { return 0; }
    public int available_tags () { return 0; }
    public async bool initialize_async () { return true; }
    public void click (string stationuuid) {}
    public void vote (string stationuuid) {}
    public async Set<Tag> get_tags_async (int offset = 0, int limit = 0) throws DataError
    {
        return new HashSet<Tag> ();
    }
    public async Set<Station> by_uuids_async (Collection<string> uuids) throws DataError
    {
        return new HashSet<Station> ();
    }
    public async Set<Station> search_async (SearchParams params, uint rowcount, uint offset = 0,
                                            int priority = GLib.Priority.HIGH_IDLE) throws DataError
    {
        offsets.add (offset);
        var found = new HashSet<Station> ();
        if (offsets.size > 1)
        {
            found.add (make_station ("page-1", "One"));
            found.add (make_station ("page-2", "Two"));
            found.add (make_station ("page-3", "Three"));
        }
        return found;
    }
}

/**
 * An empty starred file in the temporary folder. The store expects the file to exist before it saves
 * (load() creates it in the app), so the tests create it too.
 */
File temp_starred_file ()
{
    var path = Path.build_filename (Environment.get_tmp_dir (),
                                    "tuner-test-starred-%u.json".printf (Random.next_int ()));
    var file = File.new_for_path (path);
    try { file.create (FileCreateFlags.PRIVATE).close (); } catch (Error e) { Test.fail (); }
    return file;
}

void remove_file (File file)
{
    try { file.delete (); } catch (Error e) {}
}

void test_station_set_does_not_skip_a_page_after_an_empty_answer ()
{
    var file = temp_starred_file ();
    var provider = new PagingProvider ();
    var network = new NetworkState ();
    network.set_online (true);
    var stars = new StarStore (file, new AppEventBus (), provider);
    var params = SearchParams () {
        text = "", countrycode = "", tags = new HashSet<string> (), order = SortOrder.VOTES, reverse = true
    };
    var set = new Tuner.StationSet (2, params, provider, stars, network);

    int first_size = -1;
    int second_size = -1;
    set.next_page_async.begin (GLib.Priority.HIGH_IDLE, (obj, res) =>
    {
        try { first_size = set.next_page_async.end (res).size; } catch (SourceError e) {}
    });
    spin (50);
    check (first_size == 0, "the failed request gives an empty page");

    set.next_page_async.begin (GLib.Priority.HIGH_IDLE, (obj, res) =>
    {
        try { second_size = set.next_page_async.end (res).size; } catch (SourceError e) {}
    });
    spin (50);
    check (second_size == 2, "the retry gives a full page");
    check (set.has_more (), "the third station shows there is more");
    check (provider.offsets.size == 2 && provider.offsets[0] == 0 && provider.offsets[1] == 0,
           "the retry asks for the same offset");

    remove_file (file);
}

void test_station_set_is_null_while_offline ()
{
    var file = temp_starred_file ();
    var provider = new PagingProvider ();
    var network = new NetworkState ();              // Offline to begin with
    var stars = new StarStore (file, new AppEventBus (), provider);
    var params = SearchParams () {
        text = "", countrycode = "", tags = new HashSet<string> (), order = SortOrder.VOTES, reverse = true
    };
    var set = new Tuner.StationSet (2, params, provider, stars, network);

    bool answered = false;
    Set<Station>? page = null;
    set.next_page_async.begin (GLib.Priority.HIGH_IDLE, (obj, res) =>
    {
        try { page = set.next_page_async.end (res); } catch (SourceError e) {}
        answered = true;
    });
    spin (50);
    check (answered && page == null, "no page while offline");
    check (provider.offsets.size == 0, "and nothing was asked of the provider");
    remove_file (file);
}

void test_stars_add_remove ()
{
    var file = temp_starred_file ();
    var events = new AppEventBus ();
    var stars = new StarStore (file, events, new FakeProvider ());
    int changed = 0;
    events.starred_stations_changed_sig.connect ((s) => { changed++; });

    var one = make_station ("uuid-1", "One");
    var two = make_station ("uuid-2", "Two");

    stars.add_station (one);
    stars.add_station (one);                       // already there: nothing happens
    stars.add_station (two);
    check (stars.contains (one) && stars.contains (two), "both starred");
    check (changed == 2, "one event per new star");
    check (stars.get_all_stations ().size == 2, "two stations");

    stars.remove_station (one);
    check (!stars.contains (one), "one removed");
    check (changed == 3, "removal reported");

    remove_file (file);
}

void test_stars_order ()
{
    var file = temp_starred_file ();
    var stars = new StarStore (file, new AppEventBus (), new FakeProvider ());
    stars.add_station (make_station ("a", "A"));
    stars.add_station (make_station ("b", "B"));
    stars.add_station (make_station ("c", "C"));

    var order = new ArrayList<string> ();
    order.add ("c");
    order.add ("a");                               // "b" is left out and goes last
    stars.reorder_stations (order);

    var names = new ArrayList<string> ();
    foreach (var s in stars.get_all_stations ())
        names.add (s.stationuuid);
    check (names.size == 3 && names[0] == "c" && names[1] == "a" && names[2] == "b", "order is c, a, b");

    remove_file (file);
}

void test_stars_notes ()
{
    var file = temp_starred_file ();
    var stars = new StarStore (file, new AppEventBus (), new FakeProvider ());
    var one = make_station ("uuid-1", "One");

    stars.set_note ("uuid-1", "hello");            // not starred: no note kept
    check (!stars.has_note ("uuid-1"), "no note on an unstarred station");

    stars.add_station (one);
    stars.set_note ("uuid-1", "  hello  ");
    check (stars.get_note ("uuid-1") == "hello", "note is trimmed");

    stars.set_note ("uuid-1", "   ");
    check (!stars.has_note ("uuid-1"), "blank text removes the note");

    stars.set_note ("uuid-1", string.nfill (StarStore.NOTE_MAX_CHARS + 50, 'x'));
    check (stars.get_note ("uuid-1").char_count () == StarStore.NOTE_MAX_CHARS, "long note is cut");

    stars.remove_station (one);
    check (!stars.has_note ("uuid-1"), "unstarring drops the note");

    remove_file (file);
}

void test_stars_saved_searches ()
{
    var file = temp_starred_file ();
    var stars = new StarStore (file, new AppEventBus (), new FakeProvider ());
    stars.add_saved_search ("jazz");
    stars.add_saved_search ("jazz");               // a set: no duplicates
    stars.add_saved_search ("rock");
    check (stars.get_all_searches ().size == 2, "two searches");
    stars.remove_saved_search ("jazz");
    check (stars.get_all_searches ().size == 1 && stars.get_all_searches ().contains ("rock"), "rock stays");
    remove_file (file);
}

void test_stars_survive_a_restart ()
{
    var file = temp_starred_file ();
    var first = new StarStore (file, new AppEventBus (), new FakeProvider ());
    first.add_station (make_station ("uuid-1", "One"));
    first.add_station (make_station ("uuid-2", "Two"));
    first.set_note ("uuid-2", "my favourite");
    first.add_saved_search ("jazz");

    // Station.basic reads the saved stations with member names the saved file does not always use, and
    // silences the resulting Json criticals. Tests make criticals fatal, so allow them for this step.
    var fatal_before = Log.set_always_fatal (LogLevelFlags.LEVEL_ERROR);

    // A new store on the same file, as after restarting the app
    var second = new StarStore (file, new AppEventBus (), new FakeProvider ());
    var loop = new MainLoop ();
    second.load.begin ((obj, res) =>
    {
        second.load.end (res);
        loop.quit ();
    });
    loop.run ();
    Log.set_always_fatal (fatal_before);

    var names = new ArrayList<string> ();
    foreach (var s in second.get_all_stations ())
        names.add (s.name);
    check (names.size == 2 && names[0] == "One" && names[1] == "Two", "stations and order kept");
    check (second.get_note ("uuid-2") == "my favourite", "note kept");
    check (!second.has_note ("uuid-1"), "no note where there was none");
    check (second.get_all_searches ().contains ("jazz"), "saved search kept");
    check (second.contains (make_station ("uuid-1", "One")), "contains looks up by uuid");

    remove_file (file);
}


// ----------------------------------------------------------
// PlayerController (with a fake stream player)
// ----------------------------------------------------------

/** A stream player that plays nothing and reports what it is asked to do. */
class FakePlayer : StreamPlayer
{
    public int plays = 0;
    public int stops = 0;
    public int crossfades = 0;

    public FakePlayer (string url) { base (url); }

    public override bool play_impl () { plays++; return true; }
    public override bool stop_impl () { stops++; return true; }
    public override bool crossfade_impl (StreamPlayer next_player, double target_volume)
    {
        crossfades++;
        next_player.play ();            // As the real player does: the fade ends with the next station playing
        return true;
    }
    public override void set_volume_level_impl (double volume) {}

    /** The stream reports a change of state, as GStreamer does. */
    public void report (StreamPlayer.State state) { update_play_state (state); }

    /** The stream reports a failure, as GStreamer does. */
    public void fail (string message) { playback_error (message); }
}

/** A player controller on a fake player, with everything it needs, and a record of what it announced. */
class PlayerRig : Object
{
    public AppEventBus events = new AppEventBus ();
    public NetworkState network = new NetworkState ();
    public StationSession session = new StationSession ();
    public Tuner.Settings settings = new Tuner.Settings ();
    public PlayerController controller;
    public ArrayList<FakePlayer> players = new ArrayList<FakePlayer> ();
    public ArrayList<StreamPlayer.State> states = new ArrayList<StreamPlayer.State> ();
    public int station_changes = 0;
    public bool machine_network = true;             // What the machine says about its network, apart from the app's state

    public PlayerRig (bool online = true)
    {
        network.set_online (online);
        controller = new PlayerController (events, settings, session, network, (url) =>
        {
            var player = new FakePlayer (url);
            players.add (player);
            return player;
        }, () => { return machine_network; });
        events.player_state_changed_sig.connect ((station, state) => { states.add (state); });
        events.station_changed_sig.connect ((station) => { station_changes++; });
    }

    public FakePlayer current { owned get { return players[players.size - 1]; } }
}

/** Run the main loop for a while: the controller waits half a second before it starts a station. */
void spin (uint milliseconds)
{
    var loop = new MainLoop ();
    Timeout.add (milliseconds, () => { loop.quit (); return Source.REMOVE; });
    loop.run ();
}

void test_player_plays_a_station ()
{
    var rig = new PlayerRig ();
    var station = make_station ("uuid-1", "One");

    rig.controller.play_station (station);
    check (rig.station_changes == 1, "station change announced at once");
    check (rig.players.size == 1, "one player made");
    check (rig.current.plays == 0, "not started yet (the controller waits to flush metadata)");

    spin (800);
    check (rig.current.plays == 1, "player started");
    check (rig.controller.player_state == StreamPlayer.State.PLAYING, "state is PLAYING");
    check (rig.states.size > 0 && rig.states[rig.states.size - 1] == StreamPlayer.State.PLAYING, "PLAYING announced");
}

void test_player_does_not_play_offline ()
{
    var rig = new PlayerRig (false);
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);

    check (rig.controller.player_state == StreamPlayer.State.STOPPED, "stays STOPPED offline");
    check (rig.current.stops >= 1, "the player was stopped");
}

void test_player_play_pause_toggles ()
{
    var rig = new PlayerRig ();
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);
    check (rig.controller.player_state == StreamPlayer.State.PLAYING, "playing");

    rig.controller.play_pause ();
    check (rig.current.stops == 1, "pause stops the player");
    check (rig.controller.player_state == StreamPlayer.State.STOPPED, "now STOPPED");

    rig.controller.play_pause ();
    check (rig.current.plays == 2, "play starts it again");
    check (rig.controller.player_state == StreamPlayer.State.PLAYING, "PLAYING again");
}

void test_player_crossfades_between_stations ()
{
    var rig = new PlayerRig ();
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);

    rig.controller.play_station (make_station ("uuid-2", "Two"));
    check (rig.players.size == 2, "second player made");
    check (rig.players[0].crossfades == 1, "first player crossfades to the second");
    check (rig.station_changes == 2, "both changes announced");
}

void test_player_reports_a_failure ()
{
    var rig = new PlayerRig ();
    var station = make_station ("uuid-1", "One");
    rig.controller.play_station (station);
    spin (800);

    // With a network, a failure is the station's fault
    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*marked broken*");
    rig.current.fail ("HTTP 403");
    Test.assert_expected_messages ();

    check (rig.controller.play_error && rig.controller.play_error_message == "HTTP 403", "error kept");
    check (rig.session.is_broken (station), "station blamed");

    rig.current.fail ("follow-on noise");           // later errors from one failure are ignored
    check (rig.controller.play_error_message == "HTTP 403", "first error is the one kept");

    rig.controller.play_station (make_station ("uuid-2", "Two"));
    check (!rig.controller.play_error, "the next station clears the error");
}

void test_player_does_not_blame_a_station_when_the_machine_has_no_network ()
{
    var rig = new PlayerRig ();
    var station = make_station ("uuid-1", "One");
    rig.controller.play_station (station);
    spin (800);

    rig.machine_network = false;                    // The app's state has not caught up yet
    rig.current.fail ("connection lost");

    check (!rig.session.is_broken (station), "the station is not blamed");
    check (!rig.controller.play_error, "the error is not kept: it says nothing about the station");
    check (rig.controller.player_state == StreamPlayer.State.STOPPED, "the player is simply stopped");
}

/** The parts of the application a coordinator asks for, built on a player rig. */
class FakeApp : Object, Tuner.AppContext
{
    private PlayerRig _rig;
    private History _history = new History ();
    private JukeboxController? _jukebox = null;
    public ConnectionCoordinator? _connection = null;          // Tests that need a connection set it
    public ArrayList<Station> played = new ArrayList<Station> ();
    public int starred_chosen = 0;

    public FakeApp (PlayerRig rig) { _rig = rig; }

    public AppEventBus events { get { return _rig.events; } }
    public StationSession session { get { return _rig.session; } }
    public History history { get { return _history; } }
    public PlayerController player { get { return _rig.controller; } }
    public JukeboxController jukebox { get { return _jukebox; } }
    public ConnectionCoordinator connection { get { return _connection; } }
    public bool is_online { get { return _rig.network.is_online; } }
    public bool is_offline { get { return _rig.network.is_offline; } }
    public string? cache_dir { get { return null; } }
    public void quit_cleanly (string reason) {}
    public void play_station_in_ui (Station station) { played.add (station); }
    public void present_window () {}
    public void choose_starred_stations () { starred_chosen++; }
    public bool render_icon (string resource, int size_px, string png_path) { return false; }
}

/** A provider whose server choice and station lookups the test decides. */
class ScriptedProvider : Object, API
{
    public DataError? last_data_error { get; protected set; }
    public API.Status status { get; protected set; default = API.Status.NOT_AVAILABLE; }
    public bool servers_answer = true;
    public int server_choices = 0;
    public Station? found = null;               // What a lookup by uuid finds
    public ArrayList<Station> queue = new ArrayList<Station> ();    // Handed out one per search, if any
    public ArrayList<uint> offsets = new ArrayList<uint> ();        // Offset of each search
    public ArrayList<string> clicks = new ArrayList<string> ();     // Stations clicked
    public ArrayList<string> votes = new ArrayList<string> ();      // Stations voted for
    public string name () { return "scripted"; }
    public int available_stations () { return 0; }
    public int available_tags () { return 0; }
    public async bool initialize_async ()
    {
        server_choices++;
        if (servers_answer)
            status = API.Status.OK;
        return servers_answer;
    }
    public void click (string stationuuid) { clicks.add (stationuuid); }
    public void vote (string stationuuid) { votes.add (stationuuid); }
    public void already_proven () { status = API.Status.OK; }
    public async Set<Tag> get_tags_async (int offset = 0, int limit = 0) throws DataError
    {
        return new HashSet<Tag> ();
    }
    public async Set<Station> by_uuids_async (Collection<string> uuids) throws DataError
    {
        var result = new HashSet<Station> ();
        if (found != null)
            result.add (found);
        return result;
    }
    public async Set<Station> search_async (SearchParams params, uint rowcount, uint offset = 0,
                                            int priority = GLib.Priority.HIGH_IDLE) throws DataError
    {
        if (params.uuids == null)
        {
            offsets.add (offset);
            var next = new HashSet<Station> ();
            if (queue.size > 0)
                next.add (queue.remove_at (0));
            return next;
        }
        return yield by_uuids_async (params.uuids);
    }
}

/** Connection coordinator, start-up flows and a record of the connection states announced. */
class StartRig : Object
{
    public PlayerRig player = new PlayerRig (false);
    public ScriptedProvider provider = new ScriptedProvider ();
    public FakeApp app;
    public ConnectionCoordinator connection;
    public DirectoryController directory;
    public ArrayList<ConnectionState> states = new ArrayList<ConnectionState> ();
    public File starred_file;

    public StartRig ()
    {
        app = new FakeApp (player);
        connection = new ConnectionCoordinator (app, player.events, provider);
        app._connection = connection;
        player.events.connection_state_changed_sig.connect ((state) => { states.add (state); });

        // A file that does not exist yet, as on a first run: loading creates it
        starred_file = File.new_for_path (Path.build_filename (Environment.get_tmp_dir (),
                                                               "tuner-test-start-%u.json".printf (Random.next_int ())));
        var stars = new StarStore (starred_file, player.events, provider);
        directory = new DirectoryController (provider, stars, player.network);
    }

    /** The network goes up or down, as CoreSession reports it. */
    public void network (bool online)
    {
        player.network.set_online (online);
        player.events.connectivity_changed_sig (online);
    }

    public StartupCoordinator startup ()
    {
        return new StartupCoordinator (app, player.events, player.settings, directory, null);
    }

    public ConnectionState last_state { get { return states[states.size - 1]; } }

    public void finish () { remove_file (starred_file); }
}

void test_connection_goes_ready_when_a_server_answers ()
{
    var rig = new StartRig ();
    rig.network (true);
    rig.connection.start ();
    check (rig.connection.state == ConnectionState.CONNECTING || rig.connection.state == ConnectionState.READY,
           "connecting at once");
    spin (100);
    check (rig.connection.state == ConnectionState.READY, "ready once a server answered");
    check (rig.provider.server_choices >= 1, "a server was chosen");
    check (rig.states.size == 2 && rig.states[0] == ConnectionState.CONNECTING && rig.states[1] == ConnectionState.READY,
           "connecting, then ready, each announced once");
    rig.finish ();
}

void test_connection_is_offline_without_a_network ()
{
    var rig = new StartRig ();
    rig.connection.start ();
    check (rig.connection.state == ConnectionState.OFFLINE, "offline");
    check (rig.provider.server_choices == 0, "no server is tried");

    rig.network (true);
    spin (100);
    check (rig.connection.state == ConnectionState.READY, "ready when the network comes");

    rig.network (false);
    check (rig.connection.state == ConnectionState.OFFLINE, "offline when it goes");
    rig.finish ();
}

void test_connection_skips_the_choice_when_a_server_is_proven ()
{
    var rig = new StartRig ();
    rig.provider.already_proven ();
    rig.network (true);
    rig.connection.start ();
    check (rig.connection.state == ConnectionState.READY, "ready at once");
    check (rig.provider.server_choices == 0, "no new choice");
    rig.finish ();
}

void test_connection_keeps_trying_when_no_server_answers ()
{
    var rig = new StartRig ();
    rig.provider.servers_answer = false;
    rig.player.network.set_online (true);           // Up before start(), with no event, so start() is the only trigger

    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*No scripted server answered*");
    rig.connection.start ();
    spin (100);
    Test.assert_expected_messages ();
    check (rig.connection.state == ConnectionState.CONNECTING, "still connecting");
    check (rig.provider.server_choices == 1, "one choice so far, the next after a wait");

    rig.network (false);                            // Cancels the retry, so it does not fire in a later test
    check (rig.connection.state == ConnectionState.OFFLINE, "offline cancels the wait");
    rig.finish ();
}

// ----------------------------------------------------------
// ServerSelector (with a prober that answers as the test says)
// ----------------------------------------------------------

/** Answers each probe after a delay, successfully or not, as the test set it up. */
class FakeProber : Object, ServerProber
{
    public HashMap<string, bool> works = new HashMap<string, bool> ();
    public HashMap<string, uint> delays = new HashMap<string, uint> ();
    public ArrayList<string> probed = new ArrayList<string> ();

    public async ProbeResult probe (string server)
    {
        probed.add (server);
        uint delay = delays.has_key (server) ? delays[server] : 0;
        if (delay > 0)
        {
            Timeout.add (delay, probe.callback);
            yield;
        }
        var result = new ProbeResult (server);
        result.ok = works.has_key (server) && works[server];
        result.latency_ms = result.ok ? (double) delay : -1.0;
        return result;
    }
}

ServerSelector make_selector (FakeProber prober, string[] servers, int max_candidates)
{
    var selector = new ServerSelector (prober, max_candidates, servers[0]);
    var names = new ArrayList<string> ();
    foreach (var name in servers)
        names.add (name);
    selector.pool.set_servers (names);
    return selector;
}

/** Runs a server choice to the end. */
ProbeResult? run_choice (ServerSelector selector)
{
    ProbeResult? answer = null;
    var loop = new MainLoop ();
    selector.choose.begin ((obj, res) =>
    {
        answer = selector.choose.end (res);
        loop.quit ();
    });
    loop.run ();
    return answer;
}

void test_selector_takes_the_first_server_to_answer ()
{
    var prober = new FakeProber ();
    prober.works["slow"] = true;
    prober.delays["slow"] = 120;
    prober.works["quick"] = true;
    prober.delays["quick"] = 10;
    prober.works["dead"] = false;
    var selector = make_selector (prober, { "slow", "quick", "dead" }, 3);

    var winner = run_choice (selector);
    check (winner != null && winner.server == "quick", "the quickest answer wins");
    check (selector.current == "quick" && selector.proven, "it is in use, and proven");
    check (prober.probed.size == 3, "all three were asked at the same time");
    spin (200);                                     // The slow probe finishes in the background
}

void test_selector_uses_the_best_ranked_when_none_answer_and_then_tries_all ()
{
    var prober = new FakeProber ();
    var selector = make_selector (prober, { "a", "b", "c" }, 1);

    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*no server answered*");
    var winner = run_choice (selector);
    Test.assert_expected_messages ();
    check (winner == null && !selector.proven, "nothing answered");
    check (prober.probed.size == 1, "only the best-ranked server was asked");

    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*no server answered*");
    run_choice (selector);
    Test.assert_expected_messages ();
    check (prober.probed.size == 4, "after a failed choice every server is asked");

    prober.works["c"] = true;
    winner = run_choice (selector);
    check (winner != null && winner.server == "c" && selector.proven && selector.current == "c",
           "a server that comes up is found");
}

void test_selector_retires_and_advances ()
{
    var prober = new FakeProber ();
    var selector = make_selector (prober, { "a", "b" }, 2);
    check (selector.current == "a", "starts on the initial server");

    for (int i = 0; i < 7; i++)
        check (!selector.record (false), "not judged yet");
    check (selector.record (false), "the 8th failure says retire it");
    selector.retire ();

    check (selector.advance (), "there is another server");
    check (selector.current == "b", "moved to it");
    check (!selector.advance (), "and no more after that");
}

/** A jukebox on the start-up rig, with three random stations waiting at the directory. */
class JukeRig : Object
{
    public StartRig rig = new StartRig ();
    public JukeboxController jukebox;
    public int state_changes = 0;
    public bool last_state = false;

    public JukeRig ()
    {
        rig.player.network.set_online (true);
        for (int i = 1; i <= 3; i++)
            rig.provider.queue.add (make_station ("juke-%d".printf (i), "Juke %d".printf (i)));
        jukebox = new JukeboxController (rig.app, rig.directory);
        jukebox.shuffle_state_changed_sig.connect ((enabled) => { state_changes++; last_state = enabled; });
    }

    public ArrayList<Station> played { get { return rig.app.played; } }
}

void test_jukebox_enable_plays_a_random_station ()
{
    var juke = new JukeRig ();
    juke.jukebox.enable ();
    spin (50);
    check (juke.jukebox.enabled && juke.state_changes == 1 && juke.last_state, "enabled, announced once");
    check (juke.played.size == 1 && juke.played[0].stationuuid == "juke-1", "the first random station plays");

    juke.jukebox.enable ();                         // Again: a new station, no new announcement
    spin (50);
    check (juke.state_changes == 1, "no second announcement");
    check (juke.played.size == 2 && juke.played[1].stationuuid == "juke-2", "a new station");
    check (juke.rig.provider.offsets.size == 2 && juke.rig.provider.offsets[0] == 0 && juke.rig.provider.offsets[1] == 1,
           "each shuffle asks with a new offset, so the answer is not cached");
    juke.rig.finish ();
}

void test_jukebox_disabled_does_nothing ()
{
    var juke = new JukeRig ();
    juke.rig.player.events.shuffle_requested_sig ();
    spin (50);
    check (juke.played.size == 0, "a shuffle request is ignored while off");

    juke.jukebox.enable ();
    spin (50);
    juke.rig.player.events.shuffle_requested_sig ();
    spin (50);
    check (juke.played.size == 2, "a request shuffles while on");

    juke.jukebox.disable ();
    check (!juke.jukebox.enabled && juke.state_changes == 2 && !juke.last_state, "disabled, announced");
    juke.jukebox.disable ();
    check (juke.state_changes == 2, "disabling twice announces once");
    juke.rig.player.events.shuffle_requested_sig ();
    spin (50);
    check (juke.played.size == 2, "off again: nothing more");
    juke.rig.finish ();
}

void test_jukebox_skips_broken_stations ()
{
    var juke = new JukeRig ();
    Test.expect_message ("Tuner", LogLevelFlags.LEVEL_WARNING, "*marked broken*");
    juke.rig.player.session.mark_broken (juke.rig.provider.queue[0], "dead");
    Test.assert_expected_messages ();

    juke.jukebox.enable ();
    spin (50);
    check (juke.played.size == 1 && juke.played[0].stationuuid == "juke-2", "the broken station is passed over");
    juke.rig.finish ();
}

void test_jukebox_moves_on_at_the_tape_milestone_and_after_an_error ()
{
    var juke = new JukeRig ();
    juke.jukebox.enable ();
    spin (50);
    check (juke.played.size == 1, "first station");

    juke.rig.player.events.tape_counter_sig (juke.played[0]);
    spin (50);
    check (juke.played.size == 2, "the milestone moves on");

    juke.rig.player.events.player_state_changed_sig (juke.played[1], StreamPlayer.State.STOPPED_ERROR);
    spin (200);
    check (juke.played.size == 2, "an error waits before moving on");
    spin (1600);
    check (juke.played.size == 3, "then moves on");

    juke.jukebox.disable ();
    juke.rig.finish ();
}

/** Usage tracking on a player rig, with a provider that records clicks and votes. */
class UsageRig : Object
{
    public PlayerRig player = new PlayerRig ();
    public ScriptedProvider provider = new ScriptedProvider ();
    public UsageTrackingCoordinator usage;

    public UsageRig (bool do_not_vote = false)
    {
        player.settings.do_not_vote = do_not_vote;
        usage = new UsageTrackingCoordinator (player.settings, player.events, provider, player.session);
    }

    public void state (Station station, StreamPlayer.State state)
    {
        player.events.player_state_changed_sig (station, state);
    }
}

void test_usage_clicks_when_a_new_station_plays ()
{
    var rig = new UsageRig ();
    var one = make_station ("usage-1", "Usage One");
    var two = make_station ("usage-1b", "Usage One B");

    rig.state (one, StreamPlayer.State.BUFFERING);
    rig.state (one, StreamPlayer.State.STOPPED);
    check (rig.provider.clicks.size == 0, "only playing counts");

    rig.state (one, StreamPlayer.State.PLAYING);
    check (rig.provider.clicks.size == 1 && rig.provider.clicks[0] == "usage-1", "a click when it plays");
    check (one.clickcount == 1 && one.clicktrend == 1, "the counts follow");

    rig.state (one, StreamPlayer.State.PLAYING);
    check (rig.provider.clicks.size == 1, "not again for the station that played last");

    rig.state (two, StreamPlayer.State.PLAYING);
    check (rig.provider.clicks.size == 2, "a click for another station");

    rig.state (one, StreamPlayer.State.PLAYING);
    check (rig.provider.clicks.size == 3 && rig.provider.clicks[2] == "usage-1", "and again when going back, with no 24-hour check");
}

void test_usage_does_nothing_when_voting_is_off ()
{
    var rig = new UsageRig (true);
    var station = make_station ("usage-2", "Usage Two");
    station.starred = true;

    rig.state (station, StreamPlayer.State.PLAYING);
    rig.player.events.station_starred_sig (station);
    check (rig.provider.clicks.size == 0 && rig.provider.votes.size == 0, "no clicks, no votes");
    rig.player.settings.do_not_vote = false;
}

void test_usage_votes_when_a_station_is_starred ()
{
    var rig = new UsageRig ();
    var station = make_station ("usage-4", "Usage Four");
    int votes_before = station.votes;

    rig.player.events.tape_counter_sig (station);
    check (rig.provider.votes.size == 0 && rig.provider.clicks.size == 0, "the tape counter no longer votes or clicks");

    rig.player.events.station_starred_sig (station);
    check (rig.provider.votes.size == 1 && rig.provider.votes[0] == "usage-4", "a vote when it is starred");
    check (station.votes == votes_before + 1, "its votes follow");

    rig.player.events.station_starred_sig (station);
    check (rig.provider.votes.size == 2, "a vote every time it is starred");
}

void test_startup_chooses_starred_stations ()
{
    var rig = new StartRig ();
    rig.player.settings.start_on_starred = true;
    rig.player.settings.auto_play = false;
    var startup = rig.startup ();
    startup.start ();
    check (rig.app.starred_chosen == 1, "the host is asked to show starred stations");
    rig.finish ();
}

void test_autoplay_waits_for_the_connection_then_plays_once ()
{
    var rig = new StartRig ();
    rig.player.settings.start_on_starred = false;
    rig.player.settings.startup_jingle = false;
    rig.player.settings.auto_play = true;
    rig.player.settings.last_played_station = "uuid-last";
    rig.provider.found = make_station ("uuid-last", "Last");

    rig.connection.start ();                        // Offline
    var startup = rig.startup ();
    startup.start ();
    spin (100);
    check (rig.app.played.size == 0, "nothing plays before the connection is ready");

    rig.network (true);
    spin (300);
    check (rig.app.played.size == 1 && rig.app.played[0].stationuuid == "uuid-last", "the last station plays");

    rig.network (false);
    rig.network (true);
    spin (300);
    check (rig.app.played.size == 1, "once per session");
    rig.finish ();
}

void test_autoplay_does_nothing_when_it_is_off ()
{
    var rig = new StartRig ();
    rig.player.settings.startup_jingle = false;
    rig.player.settings.start_on_starred = false;
    rig.player.settings.auto_play = false;
    rig.player.settings.last_played_station = "uuid-last";
    rig.provider.found = make_station ("uuid-last", "Last");
    rig.provider.already_proven ();
    rig.network (true);
    rig.connection.start ();

    var startup = rig.startup ();
    startup.start ();
    spin (300);
    check (rig.app.played.size == 0, "nothing plays");
    rig.finish ();
}

/** The network drops (the stream stops with it) and comes back, as CoreSession reports it. */
void network_outage (PlayerRig rig)
{
    rig.network.set_online (false);
    rig.events.connectivity_changed_sig (false);
    rig.controller.stop ();
    spin (100);
    rig.network.set_online (true);
    rig.events.connectivity_changed_sig (true);
    spin (800);
}

void test_recovery_restarts_playback_after_an_outage ()
{
    var rig = new PlayerRig ();
    rig.settings.play_restart = true;
    var recovery = new PlaybackRecoveryCoordinator (new FakeApp (rig), rig.events, rig.controller, rig.settings);
    check (recovery != null, "coordinator made");
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);
    check (rig.players.size == 1, "one player to begin with");

    network_outage (rig);
    check (rig.players.size == 2, "the station is started again");
    check (rig.controller.player_state == StreamPlayer.State.PLAYING, "and plays");
}

void test_recovery_does_nothing_when_restart_is_off ()
{
    var rig = new PlayerRig ();
    rig.settings.play_restart = false;
    var recovery = new PlaybackRecoveryCoordinator (new FakeApp (rig), rig.events, rig.controller, rig.settings);
    check (recovery != null, "coordinator made");
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);

    network_outage (rig);
    check (rig.players.size == 1, "no new player");
    check (rig.controller.player_state == StreamPlayer.State.STOPPED, "still stopped");
}

void test_recovery_leaves_a_stopped_station_alone ()
{
    var rig = new PlayerRig ();
    rig.settings.play_restart = true;
    var recovery = new PlaybackRecoveryCoordinator (new FakeApp (rig), rig.events, rig.controller, rig.settings);
    check (recovery != null, "coordinator made");
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);

    rig.controller.stop ();                         // The user stops it, online
    spin (100);
    network_outage (rig);
    check (rig.players.size == 1, "a station the user stopped is not started again");
}

int count_state (PlayerRig rig, StreamPlayer.State state)
{
    int n = 0;
    foreach (var s in rig.states)
    {
        if (s == state)
            n++;
    }
    return n;
}

void test_player_holds_back_a_short_buffering_blip ()
{
    var rig = new PlayerRig ();
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);
    check (rig.controller.player_state == StreamPlayer.State.PLAYING, "playing");
    int buffering_before = count_state (rig, StreamPlayer.State.BUFFERING);

    rig.current.report (StreamPlayer.State.BUFFERING);          // A stall...
    spin (200);
    check (rig.controller.player_state == StreamPlayer.State.PLAYING, "still shown as playing");
    rig.current.report (StreamPlayer.State.PLAYING);            // ...that clears within a second
    spin (1200);
    check (rig.controller.player_state == StreamPlayer.State.PLAYING, "playing");
    check (count_state (rig, StreamPlayer.State.BUFFERING) == buffering_before, "the blip was never announced");
}

void test_player_announces_buffering_that_lasts ()
{
    var rig = new PlayerRig ();
    rig.controller.play_station (make_station ("uuid-1", "One"));
    spin (800);
    int buffering_before = count_state (rig, StreamPlayer.State.BUFFERING);

    rig.current.report (StreamPlayer.State.BUFFERING);
    spin (1300);                                                // Longer than the hold-back
    check (rig.controller.player_state == StreamPlayer.State.BUFFERING, "now shown as buffering");
    check (count_state (rig, StreamPlayer.State.BUFFERING) == buffering_before + 1, "announced once");
}

void test_player_request_station_settles_before_taking_another ()
{
    var rig = new PlayerRig ();
    var one = make_station ("uuid-1", "One");
    var two = make_station ("uuid-2", "Two");

    check (rig.controller.request_station (one), "the first station is accepted");
    check (rig.settings.last_played_station == "uuid-1", "remembered as the last played");
    check (!rig.controller.request_station (two), "a second click while the change settles is ignored");
    check (rig.players.size == 1, "only one player was made");

    spin (1400);                                                // Past the settling time
    check (!rig.controller.request_station (one), "the station already playing is ignored");
    check (rig.controller.request_station (two), "another station is accepted once it has settled");
    check (rig.settings.last_played_station == "uuid-2", "the last played follows");
}

void test_player_request_station_is_ignored_offline ()
{
    var rig = new PlayerRig (false);
    check (!rig.controller.request_station (make_station ("uuid-1", "One")), "ignored while offline");
    check (rig.players.size == 0, "nothing was made");
}

// ----------------------------------------------------------
// CoreSession (with a host that records what it is asked)
// ----------------------------------------------------------

class FakeHost : Object, Tuner.Host
{
    public int asked = 0;                           // Requests of any kind that reached the host

    public void play_station_in_ui (Station station) { asked++; }
    public void present_window () { asked++; }
    public void choose_starred_stations () { asked++; }
    public bool render_icon (string resource, int size_px, string png_path) { asked++; return false; }
    public void save_view_state () { asked++; }
    public string? startup_sound_uri () { return null; }
    public void quit_application () { asked++; }
}

void test_core_session_builds_every_service_and_asks_nothing ()
{
    var host = new FakeHost ();
    var core = new Tuner.CoreSession (host, "io.github.tuner_labs.tuner.test");

    check (core.events != null && core.settings != null && core.session != null, "events, settings, session");
    check (core.player != null && core.stars != null && core.directory != null, "player, stars, directory");
    check (core.history != null && core.all_time != null && core.jukebox != null, "history, all time, jukebox");
    check (core.tape_counter != null && core.connection != null && core.provider != null, "tape counter, connection, provider");
    check (core.network != null, "network state");

    check (host.asked == 0, "the host is not asked for anything");
    check (core.player.player_state == StreamPlayer.State.STOPPED, "nothing is playing");
    check (core.history.entries.size == 0, "no history");
    check (core.connection.state == ConnectionState.OFFLINE, "no connection is made until the session is started");
    check (core.data_dir != null && core.data_dir.has_prefix (Environment.get_variable ("XDG_DATA_HOME")),
           "it keeps its data under the folder it was given");
}

void test_history_recorder_follows_the_player ()
{
    var rig = new PlayerRig ();
    var history = new History ();
    var recorder = new HistoryRecorder (rig.events, history, rig.controller);
    check (recorder != null, "recorder made");       // It works through the event bus; this keeps it in scope
    var station = make_station ("uuid-1", "One");

    // A station announces itself (no title yet): it gets an entry
    rig.events.playback_metadata_changed_sig (station, new StreamMetadata ());
    check (history.entries.size == 1 && history.last_entry.station == station, "announcement recorded");

    // Playing and stopping reach the entry
    rig.events.player_state_changed_sig (station, StreamPlayer.State.PLAYING);
    check (history.last_entry.playing, "entry plays with the player");
    rig.events.player_state_changed_sig (station, StreamPlayer.State.STOPPED);
    check (!history.last_entry.playing, "entry stops with the player");
}

void test_player_volume ()
{
    var rig = new PlayerRig ();
    double announced = -1.0;
    rig.events.volume_changed_sig.connect ((v) => { announced = v; });

    rig.controller.volume = 0.25;
    check (announced == 0.25, "volume change announced");
    check (rig.settings.volume == 0.25, "volume saved in the settings");
    check (rig.controller.volume == 0.25, "volume read back");
}


// ----------------------------------------------------------
// Main
// ----------------------------------------------------------

void test_genre_eras_follow_the_calendar ()
{
    var eras = Tuner.Models.Genre.eras ();
    assert (eras[0] == "40s");
    assert (eras[eras.length - 1] == "Contemporary");

    // Every decade from the forties is there, and the current decade is not
    int this_decade = (new DateTime.now_local ().get_year () / 10) * 10;
    assert (eras.length == (this_decade - 1940) / 10 + 1);
    foreach (var era in eras)
        assert (era != "%ds".printf (this_decade));
    bool nineties = false;
    bool noughties = false;
    foreach (var era in eras)
    {
        nineties = nineties || era == "90s";
        noughties = noughties || era == "2000s";
    }
    assert (nineties);
    assert (noughties);
} // test_genre_eras_follow_the_calendar


int main (string[] args)
{
    // The core session makes a data folder and a starred file. Keep them out of the user's own folders: this has to
    // be set before anything asks GLib for them, which it then remembers. The cache folder is left alone: GStreamer
    // keeps its plugin registry there, and an empty one makes the tests slow and unstable.
    try
    {
        var sandbox = DirUtils.make_tmp ("tuner-test-XXXXXX");
        Environment.set_variable ("XDG_DATA_HOME", Path.build_filename (sandbox, "data"), true);
        Environment.set_variable ("XDG_CONFIG_HOME", Path.build_filename (sandbox, "config"), true);
    } catch (Error e)
    {
        stderr.printf ("Could not make a sandbox folder: %s\n", e.message);
        return 1;
    }

    Test.init (ref args);

    // Stations keep their favicons under this folder
    Tuner.Paths.cache_dir = Environment.get_tmp_dir ();

    Test.add_func ("/pool/membership", test_pool_membership);
    Test.add_func ("/pool/unknown-server", test_pool_unknown_server_is_ignored);
    Test.add_func ("/pool/retire-after-failures", test_pool_retires_after_enough_failures);
    Test.add_func ("/pool/prefers-healthy", test_pool_prefers_the_healthy_server);
    Test.add_func ("/pool/cooling-ranks-last", test_pool_cooling_server_ranks_last);

    Test.add_func ("/network/state-changes", test_network_state_changes);

    Test.add_func ("/gate/waits-until-open", test_work_gate_waits_until_open);
    Test.add_func ("/gate/open-does-not-wait", test_work_gate_open_does_not_wait);

    Test.add_func ("/session/broken-and-recovered", test_session_broken_and_recovered);
    Test.add_func ("/session/clear-all", test_session_clear_all);

    Test.add_func ("/history/append", test_history_append_and_duplicates);
    Test.add_func ("/history/titleless-replaced", test_history_titleless_entry_is_replaced);
    Test.add_func ("/history/counts", test_history_counts);
    Test.add_func ("/history/hearts", test_history_hearts);
    Test.add_func ("/history/play-time", test_history_play_time);
    Test.add_func ("/history/clear", test_history_clear);
    Test.add_func ("/history/clipboard-text", test_history_clipboard_text);

    Test.add_func ("/directory/empty-page-retry", test_station_set_does_not_skip_a_page_after_an_empty_answer);

    Test.add_func ("/directory/offline-page", test_station_set_is_null_while_offline);

    Test.add_func ("/stars/add-remove", test_stars_add_remove);
    Test.add_func ("/stars/order", test_stars_order);
    Test.add_func ("/stars/notes", test_stars_notes);
    Test.add_func ("/stars/saved-searches", test_stars_saved_searches);
    Test.add_func ("/stars/survive-restart", test_stars_survive_a_restart);

    Test.add_func ("/player/plays-a-station", test_player_plays_a_station);
    Test.add_func ("/player/offline", test_player_does_not_play_offline);
    Test.add_func ("/player/play-pause", test_player_play_pause_toggles);
    Test.add_func ("/player/crossfade", test_player_crossfades_between_stations);
    Test.add_func ("/player/failure", test_player_reports_a_failure);
    Test.add_func ("/player/volume", test_player_volume);
    Test.add_func ("/player/buffering-blip", test_player_holds_back_a_short_buffering_blip);
    Test.add_func ("/player/buffering-lasts", test_player_announces_buffering_that_lasts);
    Test.add_func ("/player/no-network-no-blame", test_player_does_not_blame_a_station_when_the_machine_has_no_network);
    Test.add_func ("/player/request-station", test_player_request_station_settles_before_taking_another);
    Test.add_func ("/player/request-station-offline", test_player_request_station_is_ignored_offline);
    Test.add_func ("/recovery/restarts", test_recovery_restarts_playback_after_an_outage);
    Test.add_func ("/recovery/restart-off", test_recovery_does_nothing_when_restart_is_off);
    Test.add_func ("/recovery/user-stopped", test_recovery_leaves_a_stopped_station_alone);
    Test.add_func ("/connection/ready", test_connection_goes_ready_when_a_server_answers);
    Test.add_func ("/connection/offline", test_connection_is_offline_without_a_network);
    Test.add_func ("/connection/proven", test_connection_skips_the_choice_when_a_server_is_proven);
    Test.add_func ("/connection/no-answer", test_connection_keeps_trying_when_no_server_answers);
    Test.add_func ("/selector/first-to-answer", test_selector_takes_the_first_server_to_answer);
    Test.add_func ("/selector/none-answer", test_selector_uses_the_best_ranked_when_none_answer_and_then_tries_all);
    Test.add_func ("/selector/retire-advance", test_selector_retires_and_advances);
    Test.add_func ("/jukebox/enable", test_jukebox_enable_plays_a_random_station);
    Test.add_func ("/jukebox/disabled", test_jukebox_disabled_does_nothing);
    Test.add_func ("/jukebox/skips-broken", test_jukebox_skips_broken_stations);
    Test.add_func ("/jukebox/milestone-and-error", test_jukebox_moves_on_at_the_tape_milestone_and_after_an_error);
    Test.add_func ("/usage/click", test_usage_clicks_when_a_new_station_plays);
    Test.add_func ("/usage/do-not-vote", test_usage_does_nothing_when_voting_is_off);
    Test.add_func ("/usage/vote", test_usage_votes_when_a_station_is_starred);
    Test.add_func ("/startup/starred", test_startup_chooses_starred_stations);
    Test.add_func ("/startup/autoplay", test_autoplay_waits_for_the_connection_then_plays_once);
    Test.add_func ("/startup/autoplay-off", test_autoplay_does_nothing_when_it_is_off);
    Test.add_func ("/history/recorder", test_history_recorder_follows_the_player);
    Test.add_func ("/genre/eras", test_genre_eras_follow_the_calendar);
    Test.add_func ("/session/builds", test_core_session_builds_every_service_and_asks_nothing);

    return Test.run ();
}
