#!/usr/bin/env python3
# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
"""
check_core_boundary.py - keep GTK and application globals out of the functional ("core") code.

Tuner is being split into a toolkit-free core and presentation layers (see SEPARATION_PLAN.md). This check
reads every Vala file under src/ and counts uses of things the core must not touch:

  gtk      Gtk, Gdk, Granite, Rsvg, Pixbuf, Cairo, Pango (the toolkit and its helper libraries)
  widgets  the Tuner.Widgets namespace
  app      the Application class (Application.instance, Application.APP_VERSION, ...)

Everything under src/ is core and is checked. Presentation code lives in the frontend repositories and is not.

It is a ratchet. scripts/core_boundary_baseline.txt lists the uses that exist today ("file<TAB>category<TAB>count").
The check fails when a file has MORE uses of a category than its baseline (or a new file/category appears), so
the core can only get cleaner. When uses are removed it says so; run with --update to lower the baseline.

Comments and string literals are ignored.

Usage:
    check_core_boundary.py [--root DIR] [--baseline FILE] [--update] [--list]

    --root DIR       project root (default: the folder above this script)
    --baseline FILE  baseline file (default: scripts/core_boundary_baseline.txt)
    --update         rewrite the baseline to the current counts (never raises it above the current state silently:
                     it prints every entry that went up and refuses unless --allow-increase is also given)
    --allow-increase with --update, accept counts higher than the baseline
    --list           print every use found (file:line category text) and exit 0

Exit status: 0 clean, 1 new violations, 2 usage or setup error.
"""

import argparse
import collections
import os
import re
import sys

CORE_DIR = "src"

CATEGORIES = collections.OrderedDict([
    ("gtk", re.compile(r"\b(?:Gtk|Gdk|Granite|Rsvg|Pixbuf|Cairo|Pango)\b")),
    ("widgets", re.compile(r"\bTuner\.Widgets\b")),
    ("app", re.compile(r"\bApplication\b")),
])


def strip_vala(text):
    """Blank out comments and string literals but keep line breaks, so line numbers stay right."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == "//":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
        elif two == "/*":
            out.append("  ")
            i += 2
            while i < n and text[i:i + 2] != "*/":
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
        elif text[i:i + 3] == '"""':
            out.append("   ")
            i += 3
            while i < n and text[i:i + 3] != '"""':
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append("   ")
            i += 3
        elif c == '"' or (c == "@" and text[i:i + 2] == '@"'):
            # a string; the expressions inside @"...$(x)..." are not scanned (rare, and never type names)
            if c == "@":
                out.append(" ")
                i += 1
            out.append(" ")
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                    continue
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append(" ")
            i += 1
        elif c == "'":
            # character literal such as 'a' or '\n'
            j = i + 1
            if j < n and text[j] == "\\":
                j += 2
            else:
                j += 1
            if j < n and text[j] == "'":
                out.append(" " * (j - i + 1))
                i = j + 1
            else:
                out.append(c)
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def scan(root):
    """Return {(file, category): [(line, text), ...]} for the core files."""
    found = collections.defaultdict(list)
    src = os.path.join(root, CORE_DIR)
    for base, _dirs, files in os.walk(src):
        for name in sorted(files):
            if not name.endswith(".vala"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            with open(path, encoding="utf-8", errors="replace") as fh:
                original = fh.read().splitlines()
            fh_text = "\n".join(original)
            stripped = strip_vala(fh_text).splitlines()
            for lineno, line in enumerate(stripped, 1):
                for category, pattern in CATEGORIES.items():
                    for _m in pattern.finditer(line):
                        found[(rel, category)].append((lineno, original[lineno - 1].strip()))
    return found


def read_baseline(path):
    baseline = {}
    if not os.path.exists(path):
        return baseline
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.rstrip("\n")
            if not raw or raw.startswith("#"):
                continue
            parts = raw.split("\t")
            if len(parts) != 3:
                sys.exit("Bad baseline line: %r" % raw)
            baseline[(parts[0], parts[1])] = int(parts[2])
    return baseline


def write_baseline(path, counts):
    header = (
        "# Core boundary baseline - uses of toolkit, widgets and the Application class in non-presentation code.\n"
        "# Written by scripts/check_core_boundary.py --update. The numbers may only go down.\n"
        "# file<TAB>category<TAB>count\n"
    )
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(header)
        for (rel, category) in sorted(counts):
            fh.write("%s\t%s\t%d\n" % (rel, category, counts[(rel, category)]))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Keep toolkit and application globals out of the core code.")
    ap.add_argument("--root", default=os.path.dirname(here))
    ap.add_argument("--baseline", default=None)
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--allow-increase", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(os.path.join(root, CORE_DIR)):
        print("No src/ folder under %s" % root, file=sys.stderr)
        return 2
    baseline_path = args.baseline or os.path.join(root, "scripts", "core_boundary_baseline.txt")

    found = scan(root)
    counts = {key: len(hits) for key, hits in found.items()}

    if args.list:
        for (rel, category) in sorted(found):
            for lineno, text in found[(rel, category)]:
                print("%s:%d  [%s]  %s" % (rel, lineno, category, text))
        return 0

    baseline = read_baseline(baseline_path)

    if args.update:
        raised = [(k, baseline.get(k, 0), v) for k, v in sorted(counts.items()) if v > baseline.get(k, 0)]
        if raised and baseline and not args.allow_increase:
            for (rel, category), old, new in raised:
                print("would raise %s [%s]: %d -> %d" % (rel, category, old, new), file=sys.stderr)
            print("Refusing to raise the baseline; fix the code or pass --allow-increase.", file=sys.stderr)
            return 1
        write_baseline(baseline_path, counts)
        print("Baseline written: %d entries, %d uses." % (len(counts), sum(counts.values())))
        return 0

    problems = []
    for key in sorted(counts):
        allowed = baseline.get(key, 0)
        if counts[key] > allowed:
            rel, category = key
            problems.append((rel, category, allowed, counts[key]))

    tighter = [(k, baseline[k], counts.get(k, 0)) for k in sorted(baseline) if counts.get(k, 0) < baseline[k]]

    if problems:
        print("Core boundary: new uses of %s in non-presentation code:" % "/".join(CATEGORIES), file=sys.stderr)
        for rel, category, allowed, now in problems:
            print("  %s  [%s]  allowed %d, found %d" % (rel, category, allowed, now), file=sys.stderr)
            for lineno, text in found[(rel, category)]:
                print("      line %d: %s" % (lineno, text), file=sys.stderr)
        print("Move the code to a frontend repository (or behind the Host interface); see SEPARATION_PLAN.md.", file=sys.stderr)
        return 1

    total = sum(counts.values())
    print("Core boundary OK: %d uses in %d files (baseline %d)." % (
        total, len({k[0] for k in counts}), sum(baseline.values())))
    if tighter:
        print("Fewer uses than the baseline - run scripts/check_core_boundary.py --update to lock it in:")
        for (rel, category), old, new in tighter:
            print("  %s  [%s]  %d -> %d" % (rel, category, old, new))
    return 0


if __name__ == "__main__":
    sys.exit(main())
