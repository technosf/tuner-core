# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Functional code: no toolkit. See SEPARATION_PLAN.md.
core_sources = files (
    'Core/AppConstants.vala',
    'Core/AppContext.vala',
    'Core/CoreSession.vala',
    'Core/Host.vala',
    'Core/Locales.vala',
    'Core/Paths.vala',

    'Events/AppEventBus.vala',

    'Ext/GstFader.vala',
    'Ext/GstStreamPlayer.vala',

    'Coordinators/ConnectionCoordinator.vala',
    'Coordinators/HistoryRecorder.vala',
    'Coordinators/PlaybackRecoveryCoordinator.vala',
    'Coordinators/StartupCoordinator.vala',
    'Coordinators/UsageTrackingCoordinator.vala',

    'Controllers/DirectoryController.vala',
    'Controllers/JukeboxController.vala',
    'Controllers/PlayerController.vala',
    'Controllers/TapeCounterController.vala',

    'Models/Countries.vala',
    'Models/Languages.vala',
    'Models/Genre.vala',
    'Models/Station.vala',
    'Models/Favicon.vala',
    'Models/StreamPlayer.vala',
    'Models/StreamMetadata.vala',
    'Models/History.vala',
    'Models/HeartedArchive.vala',
    'Models/StationSession.vala',
    'Models/StationListBoxPager.vala',

    'Providers/RadioBrowser.vala',
    'Providers/RadioBrowserServers.vala',

    'Services/DBusMediaPlayer.vala',
    'Services/MprisArtwork.vala',
    'Services/DBusInterface.vala',
    'Services/DataProvider.vala',
    'Services/HttpClient.vala',
    'Services/MusicBrainzSearch.vala',
    'Services/NetworkState.vala',
    'Services/ServerPool.vala',
    'Services/ServerSelector.vala',
    'Services/ServerDirectory.vala',
    'Services/WorkGate.vala',
    'Services/StarStore.vala',

    'Settings.vala',
    'Utils.vala'
)

# The core as a static library. Its vapi is generated and picked up by anything that links it (meson passes
# the vapi of a linked Vala library to valac), so the frontend only sees the core's public API.
core_lib = static_library (
    'tuner-core',
    core_sources,
    config_file,
    dependencies: core_dependencies,
    vala_args: vala_args + ['--pkg', 'posix'],
    vala_header: 'tuner-core.h',
    vala_vapi: 'tuner-core.vapi'
)

core_dep = declare_dependency (
    link_with: core_lib,
    include_directories: include_directories ('.'),
    dependencies: core_dependencies
)
