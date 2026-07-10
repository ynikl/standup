#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PLIST="$ROOT/Apps/Watch/Info.plist"

watch_only=$(plutil -extract WKWatchOnly raw "$PLIST")
if [ "$watch_only" != "true" ]; then
    echo "Watch app must declare WKWatchOnly=true" >&2
    exit 1
fi
