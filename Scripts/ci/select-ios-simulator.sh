#!/usr/bin/env bash

set -euo pipefail

if [[ -n "${IRPLAYER_SIMULATOR_ID:-}" ]]; then
    if ! xcrun simctl list devices available | grep -Fq "$IRPLAYER_SIMULATOR_ID"; then
        echo "IRPLAYER_SIMULATOR_ID is not an available simulator: $IRPLAYER_SIMULATOR_ID" >&2
        exit 1
    fi

    printf '%s\n' "$IRPLAYER_SIMULATOR_ID"
    exit 0
fi

simulator_id="$(
    xcrun simctl list devices available |
        sed -nE '/^-- iOS/,/^-- / {
            /iPhone/ {
                s/.*\(([0-9A-Fa-f-]{36})\).*/\1/p
            }
        }' |
        head -n 1
)"

if [[ -z "$simulator_id" ]]; then
    echo "No available iPhone simulator was found in the active Xcode installation." >&2
    exit 1
fi

printf '%s\n' "$simulator_id"
