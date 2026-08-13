#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PLIST="$ROOT/Apps/Watch/Info.plist"
PROJECT_YML="$ROOT/project.yml"

wk_application=$(plutil -extract WKApplication raw "$PLIST")
if [ "$wk_application" != "true" ]; then
    echo "Watch app must declare WKApplication=true" >&2
    exit 1
fi

companion=$(plutil -extract WKCompanionAppBundleIdentifier raw "$PLIST")
if [ "$companion" != "com.standup.app" ]; then
    echo "Watch app must declare WKCompanionAppBundleIdentifier=com.standup.app" >&2
    exit 1
fi

if plutil -extract WKWatchOnly raw "$PLIST" >/dev/null 2>&1; then
    echo "Watch app must not declare WKWatchOnly; it is a companion app now" >&2
    exit 1
fi

if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER: com.standup.app.watchkitapp" "$PROJECT_YML"; then
    echo "Watch target bundle id must be com.standup.app.watchkitapp (prefixed by the iOS app id)" >&2
    exit 1
fi

if ! grep -q "target: StandUpWatch" "$PROJECT_YML"; then
    echo "StandUpiOS must depend on StandUpWatch so the watch app is embedded" >&2
    exit 1
fi
