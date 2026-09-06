#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
    printf 'usage: %s BINARY FRAMEWORK BINARY_NAME\n' "$0" >&2
    exit 2
fi

readonly binary="$1"
readonly framework="$2"
readonly framework_binary="$3"

case "$framework/$framework_binary" in
    Security/Security|CoreFoundation/CoreFoundation) ;;
    *)
        printf 'error: unsupported Apple framework dependency: %s/%s\n' \
            "$framework" "$framework_binary" >&2
        exit 2
        ;;
esac

[ -f "$binary" ] || {
    printf 'error: Mach-O binary does not exist: %s\n' "$binary" >&2
    exit 2
}
command -v lipo >/dev/null 2>&1 || {
    printf 'error: lipo is required\n' >&2
    exit 2
}
command -v otool >/dev/null 2>&1 || {
    printf 'error: otool is required\n' >&2
    exit 2
}

architectures="$(lipo -archs "$binary")"
[ -n "$architectures" ] || {
    printf 'error: Mach-O binary has no architectures: %s\n' "$binary" >&2
    exit 1
}

readonly dependency_pattern="^[[:space:]]*/System/Library/Frameworks/${framework}\\.framework/(Versions/A/)?${framework_binary} \\(" 
for architecture in $architectures; do
    if ! otool -arch "$architecture" -L "$binary" |
        LC_ALL=C grep -E "$dependency_pattern" >/dev/null; then
        printf 'error: %s is missing %s.framework for architecture %s\n' \
            "$binary" "$framework" "$architecture" >&2
        exit 1
    fi
done
