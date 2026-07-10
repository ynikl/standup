#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IOS_DIR="$ROOT/Apps/iOS"
IOS_DASHBOARD="$ROOT/Apps/iOS/DashboardView.swift"
IOS_APP="$ROOT/Apps/iOS/StandUpiOSApp.swift"
WATCH_APP="$ROOT/Apps/Watch/StandUpWatchApp.swift"
WATCH_ROOT="$ROOT/Apps/Watch/WatchRootView.swift"

for forbidden in \
    'StatusHero(' \
    'IgnoreActionsView' \
    'PermissionBanner' \
    'model.refresh()'
do
    if rg --quiet --fixed-strings "$forbidden" "$IOS_DASHBOARD"; then
        echo "iPhone dashboard must not own live sessions: $forbidden" >&2
        exit 1
    fi
done

if rg --quiet --fixed-strings 'model.ignore(' "$IOS_DIR"; then
    echo "iPhone views must not control the Watch session" >&2
    exit 1
fi

for forbidden in \
    'model.requestPermissions()' \
    'model.refresh()'
do
    if rg --quiet --fixed-strings "$forbidden" "$IOS_APP"; then
        echo "iPhone app must not start live-session services: $forbidden" >&2
        exit 1
    fi
done

for required in \
    'StandUpAppModel(managesReminders: false)' \
    'cancelSedentaryReminders()'
do
    if ! rg --quiet --fixed-strings "$required" "$IOS_APP"; then
        echo "iPhone app is missing review-only reminder ownership: $required" >&2
        exit 1
    fi
done

for required in \
    'model.refresh()' \
    'motion.start' \
    'model.ingest(activity: signal)' \
    'await model.requestPermissions()'
do
    if ! rg --quiet --fixed-strings "$required" "$WATCH_APP"; then
        echo "Watch app is missing live-session ownership: $required" >&2
        exit 1
    fi
done

if ! rg --quiet --fixed-strings 'model.ignore(duration)' "$WATCH_ROOT"; then
    echo "Watch skip control must remain available" >&2
    exit 1
fi
