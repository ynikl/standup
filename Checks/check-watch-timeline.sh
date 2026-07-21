#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VIEW="$ROOT/Apps/Watch/WatchRootView.swift"

rg -q '@State private var timelineStart = Date\(\)' "$VIEW"
rg -q 'TimelineView\(\.periodic\(from: timelineStart, by: 60\)\)' "$VIEW"
if rg -q 'TimelineView\(\.periodic\(from: \.now, by: 60\)\)' "$VIEW"; then
    echo "Watch timeline must not recreate its schedule from .now during body evaluation" >&2
    exit 1
fi

rg -q --fixed-strings 'return "校准中"' "$VIEW"
rg -q --fixed-strings '"运动数据暂停"' "$VIEW"
rg -q --fixed-strings '"exclamationmark.triangle.fill"' "$VIEW"
