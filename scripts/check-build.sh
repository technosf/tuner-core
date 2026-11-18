#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# check-build.sh - configure, compile and test the native build, and keep the output in build.log
# (in the repository root, ignored by git) so it can be read afterwards.
#
# Usage: scripts/check-build.sh [BUILD_DIR [MESON_SETUP_ARGS...]]      (default: build/meson)
#   e.g. scripts/check-build.sh build/meson
#
# Needs meson, ninja, valac and the development packages listed in .github/workflows/ci.yml.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${1:-build/meson}"
shift || true
extra=("$@")
log="$root/build.log"

cd "$root"
{
    echo "== $(date -Is)  $(git rev-parse --short HEAD 2>/dev/null)  $dir"
    if [ -d "$dir" ]; then
        meson setup --reconfigure "$dir" --buildtype=debug ${extra[@]+"${extra[@]}"}
    else
        meson setup "$dir" --buildtype=debug ${extra[@]+"${extra[@]}"}
    fi
    status=$?
    if [ $status -eq 0 ]; then
        meson compile -C "$dir"
        status=$?
    fi
    if [ $status -eq 0 ]; then
        meson test -C "$dir" --print-errorlogs
        status=$?
    fi
    echo "== exit status $status"
    exit "$status"
} 2>&1 | tee "$log"
exit "${PIPESTATUS[0]}"
