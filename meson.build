# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

##
## Tuner core meson build file
##
## The functional core, with no toolkit: a static library with its vapi (core_dep), the headless tests, and the
## GSettings schema. Presentation layers (tuner-gtk3, tuner-gtk4) build it as a meson subproject.
##

project (
    'io.github.tuner_labs.tuner',
    'vala', 'c',
    version: '3.0.0-beta.1',      # The core's own version (semver): the presentation layers report it and name the one they need
    meson_version: '>= 1.3.2',
)

message('Starting build for project: ' + meson.project_name())

# For a parent project that builds this as a subproject: the core's version
core_version = meson.project_version()

##
## Local debug build - let vala compiler know
##

vala_args = []

debug_local = get_option('debug') and get_option('prefix') != '/app'
if debug_local
  message('DEBUG_LOCAL')
  vala_args += ['--define=DEBUG_LOCAL']
endif

message('Build type: ' + get_option('buildtype'))

##
## Translations: the gettext domain, and where the catalogues are looked for
##

add_project_arguments (
    '-DGETTEXT_PACKAGE="@0@"'.format (meson.project_name ()),
    # The log domain of the app's own messages: G_MESSAGES_DEBUG=Tuner shows them without the noise of
    # G_MESSAGES_DEBUG=all (libsoup, GIO, GTK)
    '-DG_LOG_DOMAIN="Tuner"',
    language: 'c'
)

config_data = configuration_data()

if debug_local
    ## Local debug build: the presentation layer installs translations to its build dir
    config_data.set_quoted('LOCALEDIR', join_paths(meson.global_build_root(), 'po'))
else
    config_data.set_quoted('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
endif

config_data.set_quoted('GETTEXT_PACKAGE', meson.project_name())
config_data.set_quoted('VERSION', meson.project_version())
config_file = configure_file(
    input: 'src/Config.vala.in',
    output: '@BASENAME@',
    configuration: config_data
)

##
## Listing dependencies
##
# The core (functional code) needs no toolkit
core_dependencies = [
    dependency ('glib-2.0'),
    dependency ('gee-0.8'),
    dependency ('gio-2.0'),
    dependency ('gio-unix-2.0'),
    dependency ('gstreamer-1.0'),
    dependency ('libsoup-3.0'),
    dependency ('json-glib-1.0')
]

cc = meson.get_compiler('c')
core_dependencies += cc.find_library('m', required: true)

##
## Core library (static); every presentation layer links it
##
subdir ('src')

# Headless tests, when building the core on its own
if not meson.is_subproject()
    subdir ('tests')
endif

# A presentation layer that builds the core as a subproject reads core_dep, or asks for it by name
meson.override_dependency ('tuner-core', core_dep)

subdir ('data')

# Where the compiled settings schema is in the build tree, for a presentation layer that runs from its build folder
# (GSETTINGS_SCHEMA_DIR)
core_schema_dir = meson.project_build_root () / 'data'

##
## Tests
##

# Core boundary (see SEPARATION_PLAN.md): the functional code must not gain GTK, widget or Application
# dependencies. Needs only python3, no display.
python = find_program('python3', required: false)
if python.found() and not meson.is_subproject()
  test(
    'core-boundary',
    python,
    args: [
      files('scripts/check_core_boundary.py'),
      '--root', meson.project_source_root()
    ],
    suite: 'boundary'
  )
endif

message('Build for project: ' + meson.project_name() + ' finished.\n')
