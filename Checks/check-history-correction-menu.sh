#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VIEW="$ROOT/Apps/iOS/HistoryView.swift"

for required in \
    'Menu {' \
    'ForEach(CorrectionReason.allCases, id: \.rawValue)' \
    'if record.isExcludedFromStats' \
    '.frame(width: 44, height: 44)' \
    '.accessibilityLabel(' \
    'model.correct(recordID: record.id, reason: reason)' \
    'model.restore(recordID: record.id)'
do
    if ! rg --quiet --fixed-strings "$required" "$VIEW"; then
        echo "History correction menu is missing: $required" >&2
        exit 1
    fi
done

if rg --quiet --fixed-strings '.swipeActions(' "$VIEW"; then
    echo "History correction actions must use the visible menu instead of crowded swipes" >&2
    exit 1
fi
