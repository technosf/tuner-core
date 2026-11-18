/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file UsageTrackingCoordinator.vala
 */

using Tuner.Controllers;
using Tuner.Ext;
using Tuner.Events;
using Tuner.Models;
using Tuner.Services;

namespace Tuner.Coordinators {

	/**
	 * @brief Coordinates provider click/vote tracking from player events.
	 */
	public class UsageTrackingCoordinator : GLib.Object
	{
		private Settings _settings;
		private AppEventBus _events;
		private DataProvider.API _provider;
		private StationSession _session;

		private ulong _player_state_handler_id = 0;
		private ulong _starred_handler_id = 0;

		/** @brief The station that played last in this session: replaying it (resume, buffering) is not a new click */
		private string _last_played_uuid = "";


		/**
		 * @brief Creates a usage tracking coordinator for player-driven provider events.
		 *
		 * @param settings Application settings that gate vote/click behavior.
		 * @param events App-level event bus used for player and star events.
		 * @param provider Data provider that receives click/vote notifications.
		 * @param session Session station records (not used for clicks any more; kept for the constructor's callers).
		 */
		public UsageTrackingCoordinator(
			Settings settings,
			AppEventBus events,
			DataProvider.API provider,
			StationSession session
		) {
			Object();
			_settings = settings;
			_events = events;
			_provider = provider;
			_session = session;

			_player_state_handler_id = _events.player_state_changed_sig.connect((station, state) => {
				on_player_state_changed(station, state);
			});

			_starred_handler_id = _events.station_starred_sig.connect((station) => {
				on_station_starred(station);
			});
		}


		/**
		 * @brief Sends a click for the station.
		 *
		 * No local 24-hour check: radio-browser takes care of repeat clicks itself.
		 */
		private void send_click(Station station)
		{
			_provider.click(station.stationuuid);
			station.clickcount++;
			station.clicktrend++;
		}


		/**
		 * @brief Handles player-state transitions for provider click tracking.
		 *
		 * A click is sent each time a station starts playing that was not the last station played in this
		 * session, if vote tracking is enabled. Resuming or re-buffering the same station is not a new play;
		 * going to another station and back is.
		 *
		 * @param station Station associated with the state transition.
		 * @param state New player state.
		 */
		private void on_player_state_changed(Station station, StreamPlayer.State state)
		{
			if (state != StreamPlayer.State.PLAYING)
				return;

			bool new_station = station.stationuuid != _last_played_uuid;
			_last_played_uuid = station.stationuuid;

			if (new_station && !_settings.do_not_vote)
				send_click(station);
		}


		/**
		 * @brief Sends a vote each time the user stars a station, if vote tracking is enabled.
		 *
		 * @param station The station that was starred.
		 */
		private void on_station_starred(Station station)
		{
			if (_settings.do_not_vote)
				return;

			_provider.vote(station.stationuuid);
			station.votes++;
		}


		/**
		 * @brief Disconnects coordinator signal handlers and releases resources.
		 */
		public override void dispose()
		{
			if (_player_state_handler_id > 0)
			{
				_events.disconnect(_player_state_handler_id);
				_player_state_handler_id = 0;
			}

			if (_starred_handler_id > 0)
			{
				_events.disconnect(_starred_handler_id);
				_starred_handler_id = 0;
			}

			base.dispose();
		}
	}
}
