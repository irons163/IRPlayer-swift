#!/usr/bin/env bash

set -euo pipefail

[ "$#" -eq 1 ] || {
    printf 'usage: %s FRAMEWORKS_ROOT\n' "$0" >&2
    exit 2
}

readonly frameworks_root="$(cd "$1" && pwd)"
while IFS= read -r framework; do
    plist="$(find "$framework" -type f -name Info.plist -print | LC_ALL=C sort | head -n 1)"
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
    binary="$framework/$executable"
    relative="${framework#$frameworks_root/}"
    printf 'framework=%s\n' "$relative"
    printf 'bundle_identifier=%s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
    printf 'plist_sha256=%s\n' "$(shasum -a 256 "$plist" | awk '{ print $1 }')"
    printf 'signed_binary_sha256=%s\n' "$(shasum -a 256 "$binary" | awk '{ print $1 }')"
    architectures="$(lipo -archs "$binary")"
    printf 'architectures=%s\n' "$architectures"
    for architecture in $architectures; do
        printf 'arch=%s text_sha256=%s symbols_sha256=%s dependencies_sha256=%s install_name_sha256=%s\n' \
            "$architecture" \
            "$(otool -arch "$architecture" -s __TEXT __text "$binary" | tail -n +2 | shasum -a 256 | awk '{ print $1 }')" \
            "$(nm -arch "$architecture" -gj "$binary" | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')" \
            "$(otool -arch "$architecture" -L "$binary" | tail -n +2 | shasum -a 256 | awk '{ print $1 }')" \
            "$(otool -arch "$architecture" -D "$binary" | tail -n +2 | shasum -a 256 | awk '{ print $1 }')"
    done
done < <(find "$frameworks_root" -type d -name '*.framework' -print | LC_ALL=C sort)
