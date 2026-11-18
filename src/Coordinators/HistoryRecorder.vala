/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file HistoryRecorder.vala
 *
 * @brief Keeps the session History up to date from player events.
 */

using Tuner.Controllers;
using Tuner.Events;
using Tuner.Models;

namespace Tuner.Coordinators
{
    /**
     * @brief Records what plays into the session History.
     *
     * Each track the station announces becomes a History entry, and the entry that is playing is told when
     * playback starts and stops, so it counts play time. This used to be done by the GTK3 header bar, so a
     * second frontend had no history; it belongs to the core.
     */
    public class HistoryRecorder : GLib.Object
    {
        private History _history;
        private PlayerController _player;


        /**
         * @param events App-level event bus
         * @param history The session History to record into
         * @param player The player, read for its state when a track is announced
         */
        public HistoryRecorder (AppEventBus events, History history, PlayerController player)
        {
            Object ();
            _history = history;
            _player = player;

            events.playback_metadata_changed_sig.connect ((station, metadata) =>
            {
                _history.append (station, metadata.title);
                _history.sync_play_state (station, _player.player_state);
            });

            events.player_state_changed_sig.connect ((station, state) =>
            {
                _history.sync_play_state (station, state);
            });
        } // HistoryRecorder
    } // HistoryRecorder
} // Tuner.Coordinators
