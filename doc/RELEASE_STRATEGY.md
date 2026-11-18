# Repositories, Flathub and release strategy

Status: planning notes. Nothing here is done yet unless ticked.

## Goals

1. Flathub packaging, published as `io.github.tuner_labs.tuner`.
2. Local native builds (debug against local core code; release against a pinned core).
3. A possible webapp, sharing the common core where that is possible.

## Core is a static library

`tuner-core` builds as a static library with a generated vapi (`core_dep`). Consequences:

- Core is compiled into the frontend's single executable. No `libtuner-core.so`, `.pc`, `.vapi` or headers ship in the Flatpak, and there is no soname or ABI to maintain.
- Core contributes to `/app` only its GSettings schema (and the translation catalogue if core owns the gettext domain). The executable, desktop file, metainfo, icons, gresource and `po/` come from the frontend repo.
- The Flathub manifest needs no separate core module; core's source is simply present at `subprojects/tuner-core` when the app is built.
- A shared core would instead need its own module, installed headers/vapi, and a `.so` in `/app/lib`.
- If two frontends were ever shipped, each carries its own copy of core; a core fix means releasing both.
- Core's meson already treats prefix `/app` as a release build (`debug_local` is off), so `LOCALEDIR` points at the installed location.

## Flathub

- Flathub has one repo, `flathub/io.github.tuner_labs.tuner`, holding only the manifest.
- The main module builds the `tuner` (GTK4) repo with meson; core is supplied as a source at `subprojects/tuner-core`, pinned to a tag or commit. Flathub builds offline, so nothing is fetched at build time, and a symlink to a neighbouring checkout cannot be used.
- Modules not in the GNOME runtime go in the manifest first: `libgee` and very likely `libqrencode`. librsvg must be >= 2.52 in the target runtime. Check the runtime's GStreamer plugins cover MP3, AAC and Ogg.
- Names to line up: the manifest `command:`, the desktop file, metainfo `<id>` and icons (all named `io.github.tuner_labs.tuner.*`), and the GSettings schema ID (already `io.github.tuner_labs.tuner`).
- The MPRIS artwork code draws icons from `/io/github/tuner_labs/tuner/icons/...` resources, supplied by the frontend's gresource. Keep those paths.

## Repos

| Repo | Role |
|---|---|
| `tuner-core` | Toolkit-free logic, tests, GSettings schema. Tagged (semver); `meson dist` tarball. |
| `tuner` | The product: the GTK4 frontend, desktop file, metainfo, icons, `po/`. What Flathub and distros build. |
| `tuner-web` | Web frontend, if built (see below). |
| `tuner-gtk3` | Frozen; the current GTK3 app. |
| `flathub/io.github.tuner_labs.tuner` | Manifest only. |

Rename plan:

1. [ ] Get the GTK4 frontend running well (see `tuner-gtk4/doc/TODO_WIDGETS.md`).
2. [ ] Check nothing external points at the old `tuner` URL (existing Flathub manifest, CI badges, distro packages); renames leave a redirect.
3. [ ] Rename the current `tuner` repo to `tuner-gtk3` (stars and issues stay with it).
4. [ ] Rename the GTK4 repo to `tuner` (a freed name can be taken by a new repo; the old redirect is dropped).
5. [ ] Rename the gtk4 meson project and app ID to `io.github.tuner_labs.tuner`. Core's project is currently named that too and its `GETTEXT_PACKAGE` derives from it: rename core's project to `tuner-core` and set its gettext domain explicitly.
6. [ ] Keep `po/`, metainfo and the desktop file in `tuner`.

## Pinning core: two git sources vs submodule

The difference is where the pin to a core version is recorded; the built result is identical.

**Two git sources: the pin lives in the Flathub manifest.**

```yaml
sources:
  - type: git
    url: https://github.com/tuner-labs/tuner.git
    tag: v1.0.0
  - type: git
    url: https://github.com/tuner-labs/tuner-core.git
    tag: v3.1.0
    dest: subprojects/tuner-core
```

- `tuner` knows nothing about core; a plain clone has no core.
- Local development is unchanged: `subprojects/tuner-core` stays a git-ignored symlink to the working `tuner-core`.
- A release bumps two pins in the manifest (the external data checker can do both).
- Lowest friction while core is changing quickly.

**Git submodule: the pin lives in the `tuner` repo.**

- `.gitmodules` plus a recorded core commit; the manifest lists only the `tuner` source and flatpak-builder fetches the submodule.
- A fresh `git clone --recurse-submodules` builds; the pin cannot drift.
- Core is a real checkout at `subprojects/tuner-core`: edit and commit there, then commit in `tuner` to move the pointer. Push core before pushing the `tuner` commit that points at it, or other clones cannot fetch it.
- GitHub's auto "Source code" archives omit submodules; publish a `meson dist --include-subprojects` tarball for distro packagers (Flathub builds from the git tag and is unaffected).

Decision (for now): two git sources. Move to a submodule when core settles and fresh-clone builds for contributors matter. Switching needs no code change.

## Release flow

1. Develop core; its tests run in core's CI.
2. Tag `tuner-core` (`v3.x.y`); the tag is the API contract.
3. Update the core pin used by `tuner` (manifest pin, or submodule pointer); CI builds and runs it.
4. Tag `tuner`; the Flathub manifest pins that tag.
5. Core CI also builds each frontend against core `main`, to catch API breaks before a core tag.

## Local builds

- Debug: `subprojects/tuner-core` is a symlink to the working core, so local core edits are built straight away. `debug_local` defines `DEBUG_LOCAL` and points translations at the build tree.
- Release: the same tree with a pinned core and prefix `/app` (Flatpak) or the distro prefix.
- Core's own tests run from `tuner-core` (`meson test -C build/meson`).
- Run the app with `G_MESSAGES_DEBUG=Tuner` for the app's own log lines without libsoup/GIO noise.
- Core builds in each frontend's build tree (as a subproject) and is recompiled there only when core changes. If that becomes a nuisance, core can be made installable (pkg-config, vapi, schema) with the frontend using `dependency('tuner-core', fallback: ['tuner-core', 'core_dep'])`; the cost is reinstalling core after each change.

## Webapp (open question)

A browser cannot run the Vala core or GStreamer. Options:

- **Broadway:** GTK4's Broadway backend renders the `tuner` frontend in a browser. Full reuse, but one server process per session; good for a demo, not for the public.
- **Core as a service:** a headless `tuner-server` (HTTP/WebSocket) exposing directory, stars, history and settings; the web frontend is plain JS and plays streams with the browser's `<audio>`. Core stays the single source of logic; needs a new API surface and per-user state.
- **Reimplement in TypeScript:** static hosting, but nothing shared.

Keep it in its own repo (`tuner-web`) and decide later; nothing in the layout above blocks any option.

## To do (when ready)

- [ ] Draft the Flatpak manifest for `tuner` (two-source layout, libgee and libqrencode modules, core source at `subprojects/tuner-core`).
- [ ] Confirm the schema and gresource install correctly when core is a subproject.
- [ ] Core: set the gettext domain explicitly and rename the project to `tuner-core`.
- [ ] CI: build each frontend against core `main`.
