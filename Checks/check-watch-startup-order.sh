#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/Apps/Watch/StandUpWatchApp.swift"

refresh_line=$(rg --line-number --max-count 1 --fixed-strings 'model.refresh()' "$APP" | cut -d: -f1)
motion_line=$(rg --line-number --max-count 1 --fixed-strings 'motion.start { signal in' "$APP" | cut -d: -f1)
permission_line=$(rg --line-number --max-count 1 --fixed-strings 'await model.requestPermissions()' "$APP" | cut -d: -f1)

if [ "$refresh_line" -ge "$permission_line" ] || [ "$motion_line" -ge "$permission_line" ]; then
    echo "Watch monitoring must start before notification authorization is awaited" >&2
    exit 1
fi
