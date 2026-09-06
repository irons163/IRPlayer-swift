#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [OUTPUT.mp4]" >&2
    exit 1
fi
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/../.." && pwd)"
input="$repository_root/SPMDemo/SPMDemo/fisheye-demo.mp4"
output="${1:-$repository_root/SPMDemo/SPMDemo/fisheye-ui-test.mp4}"
if [[ -e "$output" || -L "$output" ]]; then
    echo "Output already exists: $output" >&2
    exit 1
fi

# Ten identical encoded cycles give slow UI automation a 60-second window.
# -n protects the checked-in fixture and the original from accidental overwrite.
ffmpeg -nostdin -n -stream_loop 9 -i "$input" -map 0:v:0 \
    -c copy -an -map_metadata -1 -movflags +faststart "$output"
