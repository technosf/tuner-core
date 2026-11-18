# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Headless tests of the core: no display, no network, no GTK. They link only the core library.
core_tests = executable (
    'core-tests',
    files ('core-tests.vala'),
    dependencies: [core_dep],
    vala_args: vala_args + ['--pkg', 'posix']
)

# The settings tests use the schema compiled into the build tree and keep their values in memory
test (
    'core', core_tests,
    suite: 'core',
    timeout: 60,
    env: {
        'GSETTINGS_SCHEMA_DIR': meson.project_build_root () / 'data',
        'GSETTINGS_BACKEND': 'memory'
    }
)
