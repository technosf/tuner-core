/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file JukeboxController.vala
 */

using Tuner.Events;
using Tuner.Models;
using Tuner.Services;

namespace Tuner.Controllers
{
	/**
	 * @brief Automatically shuffles stations while jukebox mode is enabled.
	 *
	 * This controller listens for user shuffle requests, playback errors, and tape
	 * counter milestones. When enabled, it selects a random station and directs the
	 * player to switch tracks.
	 */
	public class JukeboxController : GLib.Object
	{
		private const uint PLAYBACK_ERROR_RETRY_DELAY_MS = 1500u;
		private const uint STALL_TIMEOUT_MS = 20000u;  // A station that has not started playing after this long is skipped
		private const uint MAX_BROKEN_SKIPS = 10u;   // Give up after this many broken stations in a row

		private AppContext _app;
		private DirectoryController _directory;
		private StationSet _random_stations;   // Long-lived: its offset advances on every shuffle
		private bool _enabled = false;
		private bool _shuffle_in_progress = false;
		private uint _error_retry_id = 0;
		private uint _stall_id = 0;

		/**
		 * @brief Whether jukebox mode is currently enabled.
		 */
		public bool enabled
		{
			get { return _enabled; }
		}


		/**
		 * @brief Emitted when jukebox mode is enabled or disabled.
		 *
		 * @param enabled True when jukebox mode is active.
		 */
		public signal void shuffle_state_changed_sig(bool enabled);


		/**
		 * @brief Constructs a new JukeboxController.
		 *
		 * @param app The application instance used for event routing.
		 * @param directory The directory controller used for random station selection.
		 */
		public JukeboxController(AppContext app, DirectoryController directory)
		{
			Object();
			_app = app;
			_directory = directory;
			_random_stations = _directory.load_random_stations(1);

			_app.events.shuffle_requested_sig.connect(() =>
			{
				if (Tuner.debug_enabled ())
					debug(@"shuffle_requested_sig received, enabled=$_enabled");
				if (_enabled)
					request_shuffle();
			});

			_app.events.player_state_changed_sig.connect((station, state) =>
			{
				// Stall watchdog: waiting for audio (BUFFERING) arms it, any other state settles it
				if (state == StreamPlayer.State.BUFFERING)
					arm_stall_watchdog();
				else
					cancel_stall_watchdog();

				if (_enabled && state == StreamPlayer.State.STOPPED_ERROR)
				{
					if (Tuner.debug_enabled ())
						debug(@"player_state_changed_sig STOPPED_ERROR while enabled, scheduling error shuffle");
					schedule_error_shuffle();
				}
			});

			// Tape counter milestone (MILESTONE_SECONDS in TapeCounterController) - the
			// station has played long enough, so move on to the next one.
			_app.events.tape_counter_sig.connect((station) =>
			{
				if (!_enabled)
					return;

				debug("tape_counter_sig milestone reached, requesting shuffle");
				request_shuffle();
			});
		} // JukeboxController


		~JukeboxController()
		{
			cancel_stall_watchdog();
			cancel_pending_error_shuffle();
		} // ~JukeboxController


		/**
		 * @brief Enable jukebox mode, or shuffle again if already enabled.
		 *
		 * Emits `shuffle_state_changed_sig` on the disabled-to-enabled transition
		 * only, but always schedules a shuffle so re-activating jukebox mode (e.g.
		 * double-clicking it again) picks a new station rather than no-op'ing.
		 */
		public void enable()
		{
			if (Tuner.debug_enabled ())
				debug(@"enable() called, was_enabled=$_enabled");

			if (!_enabled)
			{
				_enabled = true;
				shuffle_state_changed_sig(true);
				_app.events.shuffle_mode_sig(true);     // MPRIS Shuffle, and the stock icon it shows
			}

			request_shuffle();
		} // enable


		/**
		 * @brief Disable jukebox mode.
		 *
		 * Cancels any pending retry and emits `shuffle_state_changed_sig`.
		 */
		public void disable()
		{
			if (Tuner.debug_enabled ())
				debug(@"disable() called, was_enabled=$_enabled");

			if (!_enabled)
				return;

			_enabled = false;
			cancel_pending_error_shuffle();
			cancel_stall_watchdog();
			shuffle_state_changed_sig(false);
			_app.events.shuffle_mode_sig(false);
		} // disable


		/**
		 * @brief Request an immediate shuffle.
		 *
		 * No-op if jukebox mode is disabled or another shuffle is in progress.
		 */
		public void request_shuffle()
		{
			if (!_enabled || _shuffle_in_progress)
			{
				if (Tuner.debug_enabled ())
					debug(@"request_shuffle() ignored, enabled=$_enabled shuffle_in_progress=$_shuffle_in_progress");
				return;
			}

			debug("request_shuffle() starting shuffle_to_next_station()");
			shuffle_to_next_station.begin();
		} // request_shuffle


		/**
		 * @brief Select a random station and play it.
		 *
		 * The randomness comes from RadioBrowser, not from this class. How it works:
		 *
		 *  - `DirectoryController.load_random_stations(1)` builds a search with
		 *    `order = SortOrder.RANDOM` and a page size of 1.
		 *  - `RadioBrowser.get_search_query_params()` turns that into a request of
		 *    the form `limit=2&order=random&offset=N` (page size + 1, so the
		 *    StationSet can tell whether more results exist). `reverse` is omitted
		 *    because it is meaningless for a random ordering.
		 *  - The RadioBrowser server shuffles its station list on every request and
		 *    returns the first entries, so the server-side result is random.
		 *  - The request URL must differ on every call. Identical URLs are cached
		 *    somewhere between us and RadioBrowser, which returns the same "random"
		 *    station again. `offset` has no effect on a random ordering, but it is
		 *    part of the URL, so we keep ONE StationSet for the life of the
		 *    controller: each `next_page_async()` advances its offset by the page
		 *    size and gives a fresh, uncached URL. Do not create a new StationSet
		 *    per shuffle - the offset would reset to 0 and the cache would return.
		 *  - The StationSet trims the extra look-ahead station, leaving the single
		 *    station to play.
		 *
		 * No client-side randomizing, de-duplication or history filtering is done.
		 */
		public async void shuffle_to_next_station()
		{
			if (!_enabled)
				return;

			_shuffle_in_progress = true;
			try
			{
				// RadioBrowser chooses the random station; the advancing offset keeps the URL unique.
				// Stations that already failed this session are bypassed by asking for the next one.
				for (uint skipped = 0; skipped <= MAX_BROKEN_SKIPS; skipped++)
				{
					var page = yield _random_stations.next_page_async();
					if (page == null || page.size == 0)
					{
						debug("shuffle_to_next_station() got an empty page, no station change");
						return;
					}

					var station = page.to_array()[0];
					if (_app.session.is_broken(station))
					{
						if (Tuner.debug_enabled ())
							debug(@"shuffle_to_next_station() skipping broken station: $(station.name)");
						continue;
					}

					if (Tuner.debug_enabled ())
						debug(@"shuffle_to_next_station() switching to station: $(station.name)");
					_app.play_station_in_ui(station);
					cancel_stall_watchdog();    // restart the clock for the new station
					arm_stall_watchdog();
					return;
				}

				warning("shuffle_to_next_station() only found broken stations, no station change");
			}
			catch (SourceError e)
			{
				warning("Unable to shuffle playback station: %s", e.message);
			}
			finally
			{
				_shuffle_in_progress = false;
			}
		} // shuffle_to_next_station


		/**
		 * @brief Schedule a delayed shuffle after a playback error.
		 */
		private void schedule_error_shuffle()
		{
			if (Tuner.debug_enabled ())
				debug(@"schedule_error_shuffle() scheduling retry in $(PLAYBACK_ERROR_RETRY_DELAY_MS)ms");
			cancel_pending_error_shuffle();
			_error_retry_id = Timeout.add(PLAYBACK_ERROR_RETRY_DELAY_MS, () =>
			{
				_error_retry_id = 0;
				request_shuffle();
				return Source.REMOVE;
			});
		} // schedule_error_shuffle


		/**
		 * @brief Start the stall watchdog if jukebox mode is on and it is not already running.
		 *
		 * A stream can connect yet never deliver audio, leaving the player waiting and the
		 * tape counter (which only counts while playing) never reaching its milestone.
		 * If playback has not started when the watchdog fires, move on to another station.
		 */
		private void arm_stall_watchdog()
		{
			if (!_enabled || _stall_id != 0)
				return;

			// A weak reference: the timer must not keep a finished controller (and what it uses) alive
			var weak_self = WeakRef(this);
			_stall_id = Timeout.add(STALL_TIMEOUT_MS, () =>
			{
				var self = (JukeboxController?) weak_self.get();
				if (self == null)
					return Source.REMOVE;

				self._stall_id = 0;
				if (self._enabled)
				{
					debug("stall watchdog: station did not start playing, requesting shuffle");
					self.request_shuffle();
				}
				return Source.REMOVE;
			});
		} // arm_stall_watchdog


		/**
		 * @brief Cancel the stall watchdog.
		 */
		private void cancel_stall_watchdog()
		{
			if (_stall_id == 0)
				return;

			Source.remove(_stall_id);
			_stall_id = 0;
		} // cancel_stall_watchdog


		/**
		 * @brief Cancel any pending playback-error shuffle retry.
		 */
		private void cancel_pending_error_shuffle()
		{
			if (_error_retry_id == 0)
				return;

			Source.remove(_error_retry_id);
			_error_retry_id = 0;
		} // cancel_pending_error_shuffle
	} // JukeboxController
}
