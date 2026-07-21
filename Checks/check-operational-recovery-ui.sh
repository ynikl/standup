#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
MODEL="$ROOT/Apps/Shared/StandUpAppModel.swift"
SETTINGS="$ROOT/Apps/iOS/SettingsView.swift"
WATCH="$ROOT/Apps/Watch/WatchRootView.swift"

for required in \
    '@Published private(set) var isRetryingOperationalWork' \
    'func retryOperationalWork(now: Date = Date()) async'
do
    if ! rg --quiet --fixed-strings "$required" "$MODEL"; then
        echo "Operational recovery model is missing: $required" >&2
        exit 1
    fi
done

for required in \
    'Section("应用状态")' \
    'model.operationalError' \
    'model.retryOperationalWork()' \
    'ProgressView()' \
    '.disabled(model.isRetryingOperationalWork)' \
    '.frame(minHeight: 44)' \
    '.onChange(of: model.settings)' \
    'syncControls(with: settings)'
do
    if ! rg --quiet --fixed-strings "$required" "$SETTINGS"; then
        echo "iPhone recovery UI is missing: $required" >&2
        exit 1
    fi
done

for required in \
    'WatchOperationalRetryButton' \
    '.frame(width: 44, height: 44)' \
    '.accessibilityLabel("重试失败的操作")' \
    '.accessibilityHint(error)'
do
    if ! rg --quiet --fixed-strings "$required" "$WATCH"; then
        echo "Watch recovery UI is missing: $required" >&2
        exit 1
    fi
done
