#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build/shared-checks"
TARGET="$(uname -m)-apple-macosx13.0"

mkdir -p "$BUILD_DIR"

xcrun swiftc \
    -emit-library \
    -emit-module \
    -module-name StandUpCore \
    -swift-version 6 \
    -target "$TARGET" \
    -emit-module-path "$BUILD_DIR/StandUpCore.swiftmodule" \
    "$ROOT"/Sources/StandUpCore/*.swift \
    -o "$BUILD_DIR/libStandUpCore.dylib"

xcrun swiftc \
    -parse-as-library \
    -swift-version 6 \
    -target "$TARGET" \
    -I "$BUILD_DIR" \
    -L "$BUILD_DIR" \
    -lStandUpCore \
    "$ROOT/Apps/Shared/MotionActivityClassification.swift" \
    "$ROOT/Apps/Shared/NotificationScheduling.swift" \
    "$ROOT/Apps/Shared/StandUpAppModel.swift" \
    "$ROOT/Apps/Shared/StandUpStorage.swift" \
    "$ROOT/Apps/Shared/WatchConnectivityBridge.swift" \
    "$ROOT/Checks/StandUpSharedChecks/main.swift" \
    -o "$BUILD_DIR/StandUpSharedChecks"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$BUILD_DIR/StandUpSharedChecks"
