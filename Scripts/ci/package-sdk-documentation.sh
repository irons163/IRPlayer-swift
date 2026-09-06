#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 PRODUCTS_DIRECTORY OUTPUT.tar.gz" >&2
    exit 1
fi

products_directory="$1"
output_archive="$2"
if [[ ! -d "$products_directory" || -e "$output_archive" || -L "$output_archive" ]]; then
    echo "Products directory must exist and output must not already exist." >&2
    exit 1
fi

archive_list=$(mktemp)
trap 'rm -f "$archive_list"' EXIT

# DocC symbol filenames contain colons, which upload-artifact rejects. Preserve
# the complete archive inside tar instead of renaming files and breaking links.
(
    cd "$products_directory"
    find . -type d -name '*.doccarchive' -prune -print0
) > "$archive_list"
if [[ ! -s "$archive_list" ]]; then
    echo "No SDK documentation archive found in $products_directory" >&2
    exit 1
fi
COPYFILE_DISABLE=1 tar -czf "$output_archive" -C "$products_directory" --null -T "$archive_list"
