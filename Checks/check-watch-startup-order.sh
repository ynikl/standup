#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/Apps/Watch/StandUpWatchApp.swift"

if ! rg -q --fixed-strings 'startMotionMonitoring()' "$APP"; then
    echo "Watch startup must begin history-aware motion monitoring" >&2
    exit 1
fi

motion_line=$(rg --line-number --max-count 1 --fixed-strings 'startMotionMonitoring()' "$APP" | cut -d: -f1)
permission_line=$(rg --line-number --max-count 1 --fixed-strings 'await model.requestPermissions()' "$APP" | cut -d: -f1)

if [ "$motion_line" -ge "$permission_line" ]; then
    echo "Watch monitoring must start before notification authorization is awaited" >&2
    exit 1
fi

rg -q --fixed-strings '@Environment(\.scenePhase) private var scenePhase' "$APP"
rg -q --fixed-strings 'motion.start(since: model.motionRecoveryStart(now: now)) { observation in' "$APP"
rg -q --fixed-strings 'model.ingest(activity: observation.signal, now: observation.startedAt)' "$APP"
rg -q --fixed-strings '.onChange(of: scenePhase)' "$APP"
rg -q --fixed-strings 'newPhase == .active' "$APP"
