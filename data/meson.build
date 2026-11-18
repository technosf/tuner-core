##
## SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
## SPDX-License-Identifier: GPL-3.0-or-later
##
## @file meson.build
## @brief Data meson build file of the core: the GSettings schema
##
## The desktop file, metainfo, icons and resources belong to the presentation layers.
##

#
# Install schema
#
message('Installing schema...')

schemas_dir = join_paths (get_option('prefix'), get_option('datadir'), 'glib-2.0', 'schemas')
glib_compile_schemas = find_program('glib-compile-schemas')

settings_schemas = [ meson.project_name() + '.gschema.xml' ]
fs_mod = import('fs')

# Export schema XML to the build tree.
exported_schema = fs_mod.copyfile(settings_schemas[0], settings_schemas[0])

# Compile schemas in the build tree so local debug runs work without install.
custom_target(
    'export-and-compile-local-schemas',
    output: 'gschemas.compiled',
    command: [
        glib_compile_schemas,
        '--strict',
        '--targetdir',
        meson.current_build_dir(),
        meson.current_build_dir()
    ],
    depends: exported_schema,
    build_by_default: true
)

install_data(settings_schemas, install_dir: schemas_dir)

meson.add_install_script (
    glib_compile_schemas,
    schemas_dir,
    install_tag: 'schemas'
)

message('Installed schema\n')
