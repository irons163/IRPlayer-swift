#!/usr/bin/env bash

set -euo pipefail

[ "$#" -eq 1 ] || {
    printf 'usage: %s XCFRAMEWORKS_ROOT\n' "$0" >&2
    exit 2
}

readonly frameworks_root="$(cd "$1" && pwd)"
for library in libavcodec libavdevice libavfilter libavformat libavutil \
    libswresample libswscale; do
    xcframework="$frameworks_root/$library.xcframework"
    [ -d "$xcframework" ] || {
        printf 'error: missing framework: %s\n' "$xcframework" >&2
        exit 1
    }
    while IFS= read -r framework; do
        plist="$(find "$framework" -type f -name Info.plist -print | LC_ALL=C sort | head -n 1)"
        /usr/libexec/PlistBuddy -c \
            "Set :CFBundleIdentifier org.irplayer.ffmpeg.n6-1-6.$library" "$plist"
        plutil -lint "$plist" >/dev/null
        codesign --force --sign - --timestamp=none "$framework"
        codesign --verify --deep --strict "$framework"
    done < <(find "$xcframework" -type d -name "$library.framework" -print | LC_ALL=C sort)
done
