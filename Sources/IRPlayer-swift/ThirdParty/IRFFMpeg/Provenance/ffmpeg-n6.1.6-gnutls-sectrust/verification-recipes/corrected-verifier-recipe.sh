#!/usr/bin/env bash
#
# Builds an isolated FFmpeg n6.1.6 GnuTLS/SecTrust candidate for IRPlayer-swift.
#
# This script deliberately never writes Sources/IRPlayer-swift/ThirdParty.
# Its default work root is a disposable /tmp directory and all source,
# dependency, build, framework, and provenance outputs stay there.

set -euo pipefail
IFS=$'\n\t'

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly repository_root="$(cd "$script_dir/../.." && pwd)"
readonly ffmpeg_tag="n6.1.6"
readonly ffmpeg_commit="f1e3a2bf7a2f2cde936d1ed97f09a26853d20125"
readonly ffmpeg_remote="https://github.com/FFmpeg/FFmpeg.git"
readonly gmp_version="6.3.0"
readonly gmp_url="https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz"
readonly gmp_signature_url="https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz.sig"
readonly gmp_archive_sha256="a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898"
readonly nettle_version="3.10.2"
readonly nettle_url="https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz"
readonly nettle_signature_url="https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz.sig"
readonly nettle_archive_sha256="fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5"
readonly gnutls_version="3.8.13"
readonly gnutls_url="https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz"
readonly gnutls_signature_url="https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz.sig"
readonly gnutls_archive_sha256="ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e"
readonly nasm_version="2.16.03"
readonly nasm_url="https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz"
readonly nasm_archive_sha256="1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148"
readonly nasm_git_id="b9b8718a0878523d5c45f0ab583261a3ab835ae6"
readonly nasm_git_id_url="https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/git.id"
readonly isolated_pkg_config="$script_dir/isolated-pkg-config.sh"
readonly apple_framework_verifier="$script_dir/verify-apple-framework-dependency.sh"

libraries=(
    libavutil
    libswresample
    libswscale
    libavcodec
    libavformat
    libavfilter
    libavdevice
)

all_targets=(
    ios-device-arm64
    ios-simulator-arm64
    ios-simulator-x86_64
    maccatalyst-arm64
    maccatalyst-x86_64
)

# Require an explicit persistent work root. This avoids accidentally mixing
# artifacts from separate runs and keeps every write within a caller-selected,
# disposable directory below /tmp.
work_root="${IRPLAYER_FFMPEG_WORK_ROOT:-}"
jobs="${IRPLAYER_FFMPEG_JOBS:-2}"
action="all"
requested_targets=()
minimal_verification=no
patch_mode="${IRPLAYER_FFMPEG_PATCH_MODE:-auto}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '==> %s\n' "$*"
}

usage() {
    cat <<'EOF'
Usage:
  Scripts/dependencies/build-ffmpeg-6.1.6.sh [action] [target ...] [options]

Actions:
  prepare          Verify and prepare the pinned FFmpeg/dependency sources.
  build            Build one or more raw target slices.
  package-minimal  Package the arm64 device + arm64 simulator prototype.
  package          Package all five target slices into seven XCFrameworks.
  verify           Verify an existing package; add --minimal for arm64-only.
  all              prepare, build every slice, package, and verify.

Targets:
  ios-device-arm64
  ios-simulator-arm64
  ios-simulator-x86_64
  maccatalyst-arm64
  maccatalyst-x86_64

Options:
  --work-root PATH  Required isolated /tmp/irplayer-ffmpeg-review.* directory.
  --jobs COUNT      Per-build make parallelism (default: 2).
  --minimal         Verify the arm64-only prototype package.
  --without-transport-patches
                    Build a GnuTLS/GMP bootstrap without transport patches;
                    its metadata
                    marks it ineligible for transport-security acceptance.
  --help            Show this help.

Create WORK_ROOT with mktemp -d /tmp/irplayer-ffmpeg-review.XXXXXX and clone
the reviewed FFmpeg source into WORK_ROOT/source before running this script.
The source checkout must be clean and checked out at the pinned n6.1.6 commit.
The script does not fetch, alter, or replace the repository's bundled
ThirdParty binaries.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command not found: $1"
}

assert_safe_work_root() {
    [ -n "$work_root" ] ||
        die "--work-root (or IRPLAYER_FFMPEG_WORK_ROOT) is required"
    case "$work_root" in
        /*) ;;
        *) die "work root must be an absolute path: $work_root" ;;
    esac
    case "/$work_root/" in
        *'/../'*|*'/./'*) die "work root may not contain . or .. path components: $work_root" ;;
    esac
    case "$work_root" in
        /tmp/irplayer-ffmpeg-review.*|/private/tmp/irplayer-ffmpeg-review.*) ;;
        *) die "work root must be under /tmp/irplayer-ffmpeg-review.*: $work_root" ;;
    esac
    mkdir -p "$work_root"
    work_root="$(cd -P "$work_root" && pwd)"
    case "$work_root" in
        /tmp/irplayer-ffmpeg-review.*|/private/tmp/irplayer-ffmpeg-review.*) ;;
        *) die "canonical work root escapes the isolated /tmp scope: $work_root" ;;
    esac
}

contains_target() {
    local candidate="$1"
    local target
    for target in "${all_targets[@]}"; do
        [ "$target" = "$candidate" ] && return 0
    done
    return 1
}

assert_jobs() {
    case "$jobs" in
        ''|*[!0-9]*) die "--jobs must be a positive integer" ;;
    esac
    [ "$jobs" -gt 0 ] || die "--jobs must be greater than zero"
}

source_dir() {
    printf '%s/source\n' "$work_root"
}

downloads_dir() {
    printf '%s/downloads\n' "$work_root"
}

vendor_dir() {
    printf '%s/vendor\n' "$work_root"
}

build_dir() {
    printf '%s/build/%s\n' "$work_root" "$1"
}

stage_dir() {
    printf '%s/stage/%s\n' "$work_root" "$1"
}

metadata_dir() {
    printf '%s/metadata\n' "$work_root"
}

artifacts_dir() {
    printf '%s/artifacts\n' "$work_root"
}

patches_dir() {
    printf '%s/Scripts/dependencies/patches\n' "$repository_root"
}

patch_manifest_path() {
    printf '%s/patches.manifest\n' "$(metadata_dir)"
}

patch_manifest_sha_path() {
    printf '%s/patches.manifest.sha256\n' "$(metadata_dir)"
}

patch_snapshot_dir() {
    printf '%s/patches/%s\n' "$(metadata_dir)" "$(current_patch_manifest_hash)"
}

nasm_source_dir() {
    printf '%s/nasm-%s\n' "$(vendor_dir)" "$nasm_version"
}

nasm_prefix() {
    printf '%s/tools/nasm-%s\n' "$work_root" "$nasm_version"
}

nasm_archive_path() {
    printf '%s/nasm-%s.tar.xz\n' "$(downloads_dir)" "$nasm_version"
}

nasm_git_id_path() {
    printf '%s/nasm-%s.git.id\n' "$(downloads_dir)" "$nasm_version"
}

minimal_package_dir() {
    if [ "$patch_mode" = none ]; then
        printf '%s/ffmpeg-n6.1.6-gnutls-unpatched-arm64-bootstrap\n' "$(artifacts_dir)"
    else
        printf '%s/ffmpeg-n6.1.6-gnutls-sectrust-arm64-prototype\n' "$(artifacts_dir)"
    fi
}

full_package_dir() {
    if [ "$patch_mode" = none ]; then
        printf '%s/ffmpeg-n6.1.6-gnutls-unpatched-bootstrap\n' "$(artifacts_dir)"
    else
        printf '%s/ffmpeg-n6.1.6-gnutls-sectrust\n' "$(artifacts_dir)"
    fi
}

assert_pinned_source() {
    local source
    source="$(source_dir)"
    [ -d "$source/.git" ] ||
        die "pinned FFmpeg source checkout is missing: $source"

    local head
    head="$(git -C "$source" rev-parse HEAD)"
    [ "$head" = "$ffmpeg_commit" ] ||
        die "FFmpeg source HEAD is $head, expected $ffmpeg_commit"

    [ -z "$(git -C "$source" status --porcelain)" ] ||
        die "FFmpeg source checkout is dirty: $source"

    local tag_commit
    tag_commit="$(git -C "$source" rev-list -n 1 "$ffmpeg_tag")"
    [ "$tag_commit" = "$ffmpeg_commit" ] ||
        die "tag $ffmpeg_tag does not resolve to the pinned commit"

    local remote
    remote="$(git -C "$source" remote get-url origin)"
    [ "$remote" = "$ffmpeg_remote" ] ||
        die "FFmpeg source origin is $remote, expected $ffmpeg_remote"
}

list_transport_patches() {
    local patches
    [ "$patch_mode" = auto ] || return 0
    patches="$(patches_dir)"
    [ -d "$patches" ] || return 0
    find "$patches" -type f -name '*.patch' -print | LC_ALL=C sort
}

write_transport_patch_manifest() {
    local snapshot="$1"
    local mode="$2"
    local patch
    local relative
    local patch_hash
    local patch_count=0
    [ -d "$snapshot" ] || die "transport patch snapshot is missing: $snapshot"

    printf 'patch_application_order=lexicographic-path\n'
    printf 'patch_mode=%s\n' "$mode"
    while IFS= read -r patch; do
        relative="${patch#$snapshot/}"
        case "$relative" in
            ''|/*|.|..|../*|*/../*|*/./*)
                die "transport patch snapshot contains an unsafe path: $patch"
                ;;
        esac
        patch_hash="$(shasum -a 256 "$patch" | awk '{ print $1 }')"
        printf 'path=Scripts/dependencies/patches/%s\nsha256=%s\n' \
            "$relative" "$patch_hash"
        patch_count=$((patch_count + 1))
    done < <(find "$snapshot" -type f -name '*.patch' -print | LC_ALL=C sort)
    if [ "$patch_count" -eq 0 ]; then
        if [ "$mode" = none ]; then
            printf 'patches=disabled-for-bootstrap-prototype\n'
        else
            printf 'patches=none\n'
        fi
    fi
}

remove_temporary_patch_snapshot() {
    local snapshot="$1"
    local expected_prefix="$(metadata_dir)/patches.snapshot."
    case "$snapshot" in
        "$expected_prefix"*) ;;
        *) die "refusing to remove a patch snapshot outside metadata: $snapshot" ;;
    esac
    [ -d "$snapshot" ] || die "temporary patch snapshot is not a directory: $snapshot"
    rm -rf "$snapshot"
}

record_transport_patch_metadata() {
    local metadata
    local manifest
    local temporary_manifest
    local patch
    local relative
    local manifest_hash
    local copied_patches
    local temporary_snapshot
    local patch_root
    local snapshot_manifest
    metadata="$(metadata_dir)"
    manifest="$(patch_manifest_path)"
    temporary_manifest="$manifest.partial"
    patch_root="$(patches_dir)"
    temporary_snapshot="$metadata/patches.snapshot.$$"
    mkdir -p "$metadata/patches"
    [ ! -e "$temporary_snapshot" ] ||
        die "temporary transport patch snapshot already exists: $temporary_snapshot"
    mkdir "$temporary_snapshot"

    # Copy first and hash the copy. The source patch directory is owned by a
    # separate task and may change during this build; compiling only from this
    # immutable snapshot prevents a recorded hash from diverging from bytes
    # actually applied to an FFmpeg worktree.
    while IFS= read -r patch; do
        relative="${patch#$patch_root/}"
        case "$relative" in
            ''|/*|.|..|../*|*/../*|*/./*)
                die "transport patch is outside the owned patch directory: $patch"
                ;;
        esac
        mkdir -p "$temporary_snapshot/$(dirname "$relative")"
        cp "$patch" "$temporary_snapshot/$relative"
    done < <(list_transport_patches)

    write_transport_patch_manifest "$temporary_snapshot" "$patch_mode" \
        > "$temporary_manifest"
    manifest_hash="$(shasum -a 256 "$temporary_manifest" | awk '{ print $1 }')"
    copied_patches="$metadata/patches/$manifest_hash"
    if [ -e "$copied_patches" ]; then
        snapshot_manifest="$temporary_manifest.snapshot-check"
        write_transport_patch_manifest "$copied_patches" "$patch_mode" \
            > "$snapshot_manifest"
        cmp -s "$temporary_manifest" "$snapshot_manifest" ||
            die "existing transport patch snapshot disagrees with its manifest"
        rm -f "$snapshot_manifest"
        remove_temporary_patch_snapshot "$temporary_snapshot"
    else
        mv "$temporary_snapshot" "$copied_patches"
    fi
    mv "$temporary_manifest" "$manifest"
    printf '%s\n' "$manifest_hash" > "$(patch_manifest_sha_path)"
}

current_patch_manifest_hash() {
    local manifest_hash_file
    local expected
    local actual
    manifest_hash_file="$(patch_manifest_sha_path)"
    [ -f "$manifest_hash_file" ] ||
        die "patch manifest is missing; run prepare first"
    expected="$(tr -d '\n' < "$manifest_hash_file")"
    actual="$(shasum -a 256 "$(patch_manifest_path)" | awk '{ print $1 }')"
    [ "$actual" = "$expected" ] ||
        die "transport patch manifest hash does not match its recorded value"
    printf '%s\n' "$expected"
}

assert_recorded_transport_patch_snapshot() {
    local manifest
    local snapshot
    local snapshot_manifest
    manifest="$(patch_manifest_path)"
    snapshot="$(patch_snapshot_dir)"
    snapshot_manifest="$manifest.snapshot-check"
    write_transport_patch_manifest "$snapshot" "$patch_mode" \
        > "$snapshot_manifest"
    if ! cmp -s "$manifest" "$snapshot_manifest"; then
        rm -f "$snapshot_manifest"
        die "transport patch snapshot does not match its recorded manifest"
    fi
    rm -f "$snapshot_manifest"
}

list_recorded_transport_patches() {
    local snapshot
    snapshot="$(patch_snapshot_dir)"
    find "$snapshot" -type f -name '*.patch' -print | LC_ALL=C sort
}

source_tree_digest() {
    local source="$1"
    (
        cd "$source"
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
        while IFS= read -r path; do
            printf 'symlink %s %s\n' "${path#./}" "$(readlink "$path")"
        done < <(find . -type l -print | LC_ALL=C sort)
    ) | shasum -a 256 | awk '{ print $1 }'
}

assert_or_record_extracted_source() {
    local name="$1"
    local version="$2"
    local archive_hash="$3"
    local source="$4"
    local extracted_now="$5"
    local marker="$(vendor_dir)/.$name-$version.extracted-source"
    local current
    current="archive_sha256=$archive_hash\ntree_sha256=$(source_tree_digest "$source")"
    if [ "$extracted_now" = yes ]; then
        printf '%b\n' "$current" > "$marker"
    else
        [ -f "$marker" ] ||
            die "existing $name source has no authenticated extraction marker; use a fresh isolated work root"
        [ "$(cat "$marker")" = "$(printf '%b' "$current")" ] ||
            die "existing $name source differs from the archive-derived tree; use a fresh isolated work root"
    fi
}

prepare_gmp_source() {
    local downloads
    local archive
    local signature
    local gmp_source
    local extracted_now=no
    downloads="$(downloads_dir)"
    archive="$downloads/gmp-$gmp_version.tar.xz"
    signature="$archive.sig"
    gmp_source="$(vendor_dir)/gmp-$gmp_version"

    mkdir -p "$downloads" "$(vendor_dir)"
    if [ ! -f "$archive" ]; then
        log "downloading GMP $gmp_version"
        curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
            --output "$archive.partial" "$gmp_url"
        mv "$archive.partial" "$archive"
    fi

    local actual_hash
    actual_hash="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    [ "$actual_hash" = "$gmp_archive_sha256" ] ||
        die "GMP archive SHA-256 mismatch: $actual_hash"

    if [ ! -f "$signature" ]; then
        curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
            --output "$signature.partial" "$gmp_signature_url"
        mv "$signature.partial" "$signature"
    fi

    if [ ! -d "$gmp_source" ]; then
        log "extracting GMP $gmp_version"
        tar -xJf "$archive" -C "$(vendor_dir)"
        extracted_now=yes
    fi
    [ -x "$gmp_source/configure" ] ||
        die "GMP source is incomplete: $gmp_source"
    assert_or_record_extracted_source gmp "$gmp_version" \
        "$gmp_archive_sha256" "$gmp_source" "$extracted_now"
}

prepare_signed_dependency_source() {
    local name="$1"
    local version="$2"
    local archive_extension="$3"
    local url="$4"
    local signature_url="$5"
    local expected_hash="$6"
    local archive="$(downloads_dir)/$name-$version.$archive_extension"
    local signature="$archive.sig"
    local source="$(vendor_dir)/$name-$version"
    local extracted_now=no

    mkdir -p "$(downloads_dir)" "$(vendor_dir)"
    if [ ! -f "$archive" ]; then
        log "downloading $name $version"
        curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
            --output "$archive.partial" "$url"
        mv "$archive.partial" "$archive"
    fi
    local actual_hash
    actual_hash="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    [ "$actual_hash" = "$expected_hash" ] ||
        die "$name archive SHA-256 mismatch: $actual_hash"

    if [ ! -f "$signature" ]; then
        curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
            --output "$signature.partial" "$signature_url"
        mv "$signature.partial" "$signature"
    fi
    if [ ! -d "$source" ]; then
        log "extracting $name $version"
        case "$archive_extension" in
            tar.gz) tar -xzf "$archive" -C "$(vendor_dir)" ;;
            tar.xz) tar -xJf "$archive" -C "$(vendor_dir)" ;;
            *) die "unsupported dependency archive extension: $archive_extension" ;;
        esac
        extracted_now=yes
    fi
    [ -x "$source/configure" ] || die "$name source is incomplete: $source"
    assert_or_record_extracted_source "$name" "$version" "$expected_hash" \
        "$source" "$extracted_now"
}

prepare_nettle_source() {
    prepare_signed_dependency_source nettle "$nettle_version" tar.gz \
        "$nettle_url" "$nettle_signature_url" "$nettle_archive_sha256"
}

prepare_gnutls_source() {
    prepare_signed_dependency_source gnutls "$gnutls_version" tar.xz \
        "$gnutls_url" "$gnutls_signature_url" "$gnutls_archive_sha256"
}

prepare_nasm_source() {
    local downloads
    local archive
    local git_id_file
    local nasm_source
    downloads="$(downloads_dir)"
    archive="$(nasm_archive_path)"
    git_id_file="$(nasm_git_id_path)"
    nasm_source="$(nasm_source_dir)"
    mkdir -p "$downloads" "$(vendor_dir)"

    if [ ! -f "$archive" ]; then
        log "downloading NASM $nasm_version"
        curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
            --output "$archive.partial" "$nasm_url"
        mv "$archive.partial" "$archive"
    fi
    local actual_hash
    actual_hash="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    [ "$actual_hash" = "$nasm_archive_sha256" ] ||
        die "NASM archive SHA-256 mismatch: $actual_hash"

    if [ ! -f "$git_id_file" ]; then
        curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
            --output "$git_id_file.partial" "$nasm_git_id_url"
        mv "$git_id_file.partial" "$git_id_file"
    fi
    [ "$(tr -d '\n' < "$git_id_file")" = "$nasm_git_id" ] ||
        die "NASM release git.id does not match the pinned source revision"

    if [ ! -d "$nasm_source" ]; then
        log "extracting NASM $nasm_version"
        tar -xJf "$archive" -C "$(vendor_dir)"
    fi
    [ -x "$nasm_source/configure" ] ||
        die "NASM source is incomplete: $nasm_source"
}

build_nasm_tool() {
    local prefix
    local source
    local build
    local executable
    prefix="$(nasm_prefix)"
    source="$(nasm_source_dir)"
    build="$work_root/build-tools/nasm-$nasm_version"
    executable="$prefix/bin/nasm"

    if [ -x "$executable" ]; then
        "$executable" -v | grep -F "NASM version $nasm_version" >/dev/null ||
            die "isolated NASM has an unexpected version: $executable"
        return
    fi

    mkdir -p "$build" "$prefix" "$work_root/logs/build-tools"
    log "building isolated NASM $nasm_version"
    (
        cd "$build"
        "$source/configure" --prefix="$prefix"
        make -j"$jobs"
        make install
    ) 2>&1 | tee "$work_root/logs/build-tools/nasm-build.log"
    [ -x "$executable" ] || die "isolated NASM build did not install $executable"
    "$executable" -v | grep -F "NASM version $nasm_version" >/dev/null ||
        die "isolated NASM build has an unexpected version"
}

record_global_metadata() {
    local metadata
    local source
    local archive
    local signature
    local nettle_archive
    local gnutls_archive
    metadata="$(metadata_dir)"
    source="$(source_dir)"
    archive="$(downloads_dir)/gmp-$gmp_version.tar.xz"
    signature="$archive.sig"
    nettle_archive="$(downloads_dir)/nettle-$nettle_version.tar.gz"
    gnutls_archive="$(downloads_dir)/gnutls-$gnutls_version.tar.xz"
    mkdir -p "$metadata"

    {
        printf 'ffmpeg_tag=%s\n' "$ffmpeg_tag"
        printf 'ffmpeg_commit=%s\n' "$ffmpeg_commit"
        printf 'ffmpeg_tree=%s\n' "$(git -C "$source" rev-parse "$ffmpeg_commit^{tree}")"
        printf 'ffmpeg_remote=%s\n' "$(git -C "$source" remote get-url origin)"
        printf 'ffmpeg_local_tag_verification='
        if command -v gpg >/dev/null 2>&1; then
            if git -C "$source" tag -v "$ffmpeg_tag" >/dev/null 2>&1; then
                printf 'passed\n'
            else
                printf 'failed\n'
            fi
        else
            printf 'not-run-gpg-unavailable\n'
        fi
        printf 'gmp_version=%s\n' "$gmp_version"
        printf 'gmp_url=%s\n' "$gmp_url"
        printf 'gmp_sha256=%s\n' "$(shasum -a 256 "$archive" | awk '{ print $1 }')"
        printf 'gmp_signature_sha256=%s\n' "$(shasum -a 256 "$signature" | awk '{ print $1 }')"
        printf 'gmp_signature_url=%s\n' "$gmp_signature_url"
        printf 'gmp_signature_verification=external-record-passed:docs/security/source-verification.md\n'
        printf 'gmp_verified_signer_fingerprint=343C2FF0FBEE5EC2EDBEF399F3599FF828C67298\n'
        printf 'gmp_verified_signature_creation=2023-07-30T12:18:33Z\n'
        printf 'gmp_verified_signature_hash=SHA-512\n'
        printf 'gmp_verified_signer_key_sha256=50561c50f40cd9746af214c995fb219bbe7f3b9c5f038b918f5df543bb3f846f\n'
        printf 'nettle_version=%s\n' "$nettle_version"
        printf 'nettle_url=%s\n' "$nettle_url"
        printf 'nettle_sha256=%s\n' "$(shasum -a 256 "$nettle_archive" | awk '{ print $1 }')"
        printf 'nettle_signature_sha256=%s\n' "$(shasum -a 256 "$nettle_archive.sig" | awk '{ print $1 }')"
        printf 'nettle_signature_url=%s\n' "$nettle_signature_url"
        printf 'nettle_signature_verification=external-record-passed:docs/security/nettle-source-verification.md\n'
        printf 'nettle_verified_signer_fingerprint=343C2FF0FBEE5EC2EDBEF399F3599FF828C67298\n'
        printf 'nettle_verified_signature_creation=2025-06-26T18:41:09Z\n'
        printf 'nettle_verified_signature_hash=SHA-512\n'
        printf 'nettle_verified_official_keyring_sha256=1235812a12ce07515303f9ebb138225e4021342832c1465040fee2e849524888\n'
        printf 'gnutls_version=%s\n' "$gnutls_version"
        printf 'gnutls_url=%s\n' "$gnutls_url"
        printf 'gnutls_sha256=%s\n' "$(shasum -a 256 "$gnutls_archive" | awk '{ print $1 }')"
        printf 'gnutls_signature_sha256=%s\n' "$(shasum -a 256 "$gnutls_archive.sig" | awk '{ print $1 }')"
        printf 'gnutls_signature_url=%s\n' "$gnutls_signature_url"
        printf 'gnutls_signature_verification=external-record-passed:docs/security/source-verification.md\n'
        printf 'gnutls_verified_signer_fingerprint=5D46CB0F763405A7053556F47A75A648B3F9220C\n'
        printf 'gnutls_verified_signature_creation=2026-04-29T15:18:40Z\n'
        printf 'gnutls_verified_signature_hash=SHA-512\n'
        printf 'gnutls_verified_official_keyring_sha256=a47ae67e65375cedf0e0af830db4f29b29365283c1c3661a47d3d67601b9eada\n'
        printf 'gnutls_bundled_libtasn1_version=4.20.0\n'
        printf 'gnutls_bundled_unistring=yes\n'
        printf 'nasm_version=%s\n' "$nasm_version"
        printf 'nasm_url=%s\n' "$nasm_url"
        printf 'nasm_sha256=%s\n' "$(shasum -a 256 "$(nasm_archive_path)" | awk '{ print $1 }')"
        printf 'nasm_release_git_id=%s\n' "$(tr -d '\n' < "$(nasm_git_id_path)")"
        printf 'nasm_detached_signature=not-published-by-release-directory\n'
        printf 'nasm_verification=official-release-url-and-pinned-sha256-plus-git-id\n'
        printf 'patch_manifest_sha256=%s\n' "$(current_patch_manifest_hash)"
        printf 'source_date_epoch=%s\n' "$(git -C "$source" show -s --format=%ct "$ffmpeg_commit")"
        printf 'artifact_role=GnuTLS-SecTrust-candidate-not-release\n'
        printf 'minimum_ios_version=15.0\n'
        printf 'expected_slice_inventory=ios-device-arm64,ios-simulator-arm64,ios-simulator-x86_64,maccatalyst-arm64,maccatalyst-x86_64\n'
        printf 'expected_library_inventory=libavutil,libswresample,libswscale,libavcodec,libavformat,libavfilter,libavdevice\n'
        printf 'expected_transport_configuration=gnutls-enabled,securetransport-disabled,openssl-disabled,mbedtls-disabled,libtls-disabled\n'
        printf 'expected_input_capabilities=http,https,hls,rtsp,rtmp,rtmpe,ffrtmpcrypt,file\n'
        printf 'expected_platform_capabilities=AudioToolbox,VideoToolbox,AVFoundation,Security,CoreFoundation\n'
        printf '\n[xcodebuild -version]\n'
        xcodebuild -version
        printf '\n[clang]\n'
        "$(xcrun --find clang)" --version
        printf '\n[git]\n'
        git --version
        printf '\n[SDK paths]\n'
        local sdk
        for sdk in iphoneos iphonesimulator macosx; do
            printf '%s=%s\n' "$sdk" "$(xcrun --sdk "$sdk" --show-sdk-path)"
        done
    } > "$metadata/source-and-toolchain.txt"

    mkdir -p "$metadata/licenses"
    cp "$source/COPYING.LGPLv2.1" "$metadata/licenses/FFmpeg-COPYING.LGPLv2.1"
    cp "$source/COPYING.LGPLv3" "$metadata/licenses/FFmpeg-COPYING.LGPLv3"
    cp "$(vendor_dir)/gmp-$gmp_version/COPYING.LESSERv3" \
        "$metadata/licenses/GMP-COPYING.LESSERv3"
    cp "$(vendor_dir)/gmp-$gmp_version/COPYINGv3" \
        "$metadata/licenses/GMP-COPYINGv3"
    cp "$(vendor_dir)/gmp-$gmp_version/AUTHORS" \
        "$metadata/licenses/GMP-AUTHORS"
    cp "$(vendor_dir)/nettle-$nettle_version/COPYING.LESSERv3" \
        "$metadata/licenses/Nettle-COPYING.LESSERv3"
    cp "$(vendor_dir)/nettle-$nettle_version/COPYINGv2" \
        "$metadata/licenses/Nettle-COPYINGv2"
    cp "$(vendor_dir)/nettle-$nettle_version/COPYINGv3" \
        "$metadata/licenses/Nettle-COPYINGv3"
    cp "$(vendor_dir)/nettle-$nettle_version/AUTHORS" \
        "$metadata/licenses/Nettle-AUTHORS"
    cp "$(vendor_dir)/gnutls-$gnutls_version/COPYING.LESSERv2" \
        "$metadata/licenses/GnuTLS-COPYING.LESSERv2"
    cp "$(vendor_dir)/gnutls-$gnutls_version/COPYING" \
        "$metadata/licenses/GnuTLS-COPYING"
    cp "$(vendor_dir)/gnutls-$gnutls_version/README.md" \
        "$metadata/licenses/GnuTLS-README.md"
    cp "$(vendor_dir)/gnutls-$gnutls_version/AUTHORS" \
        "$metadata/licenses/GnuTLS-AUTHORS"
    cp "$(vendor_dir)/gnutls-$gnutls_version/lib/accelerated/x86/license.txt" \
        "$metadata/licenses/GnuTLS-bundled-x86-license.txt"
    cp "$(vendor_dir)/gnutls-$gnutls_version/lib/crau/LICENSE" \
        "$metadata/licenses/GnuTLS-bundled-crau-LICENSE"
    cp "$(vendor_dir)/gnutls-$gnutls_version/lib/inih/LICENSE.txt" \
        "$metadata/licenses/GnuTLS-bundled-inih-LICENSE.txt"
    cp "$(vendor_dir)/gnutls-$gnutls_version/lib/extras/licenses/CC0" \
        "$metadata/licenses/GnuTLS-bundled-extras-CC0"
    cp "$(nasm_source_dir)/LICENSE" "$metadata/licenses/NASM-LICENSE"
    shasum -a 256 "$metadata/licenses"/* > "$metadata/license-sha256sums.txt"
}

configure_target() {
    local requested="$1"
    target_name="$requested"
    case "$requested" in
        ios-device-arm64)
            sdk_name=iphoneos
            slice_family=ios-device
            slice_arch=arm64
            target_triple=arm64-apple-ios15.0
            gmp_host=aarch64-apple-darwin
            ffmpeg_arch=aarch64
            ffmpeg_cpu=armv8
            deployment_flag=-miphoneos-version-min=15.0
            ffmpeg_asm_flags=(--enable-neon --enable-asm)
            nasm_executable=
            ;;
        ios-simulator-arm64)
            sdk_name=iphonesimulator
            slice_family=ios-simulator
            slice_arch=arm64
            target_triple=arm64-apple-ios15.0-simulator
            gmp_host=aarch64-apple-darwin
            ffmpeg_arch=aarch64
            ffmpeg_cpu=armv8
            deployment_flag=-mios-simulator-version-min=15.0
            ffmpeg_asm_flags=(--enable-neon --enable-asm)
            nasm_executable=
            ;;
        ios-simulator-x86_64)
            sdk_name=iphonesimulator
            slice_family=ios-simulator
            slice_arch=x86_64
            target_triple=x86_64-apple-ios15.0-simulator
            gmp_host=x86_64-apple-darwin
            ffmpeg_arch=x86_64
            ffmpeg_cpu=x86-64
            deployment_flag=-mios-simulator-version-min=15.0
            ffmpeg_asm_flags=(--disable-neon --enable-asm --enable-x86asm)
            nasm_executable="$(nasm_prefix)/bin/nasm"
            ;;
        maccatalyst-arm64)
            sdk_name=macosx
            slice_family=maccatalyst
            slice_arch=arm64
            target_triple=arm64-apple-ios15.0-macabi
            gmp_host=aarch64-apple-darwin
            ffmpeg_arch=aarch64
            ffmpeg_cpu=armv8
            deployment_flag=
            ffmpeg_asm_flags=(--enable-neon --enable-asm)
            nasm_executable=
            ;;
        maccatalyst-x86_64)
            sdk_name=macosx
            slice_family=maccatalyst
            slice_arch=x86_64
            target_triple=x86_64-apple-ios15.0-macabi
            gmp_host=x86_64-apple-darwin
            ffmpeg_arch=x86_64
            ffmpeg_cpu=x86-64
            deployment_flag=
            ffmpeg_asm_flags=(--disable-neon --enable-asm --enable-x86asm)
            nasm_executable="$(nasm_prefix)/bin/nasm"
            ;;
        *) die "unsupported target: $requested" ;;
    esac

    sdk_path="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
    clang_path="$(xcrun --sdk "$sdk_name" --find clang)"
    clangxx_path="$(xcrun --sdk "$sdk_name" --find clang++)"
    ar_path="$(xcrun --sdk "$sdk_name" --find ar)"
    ranlib_path="$(xcrun --sdk "$sdk_name" --find ranlib)"
    nm_path="$(xcrun --sdk "$sdk_name" --find nm)"
    strip_path="$(xcrun --sdk "$sdk_name" --find strip)"
    host_clang_path="$(xcrun --sdk macosx --find clang)"
    host_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

    if [ "$slice_family" = maccatalyst ]; then
        local ios_support="$sdk_path/System/iOSSupport"
        platform_cflags="-target $target_triple -isysroot $sdk_path -isystem $ios_support/usr/include -iframework $ios_support/System/Library/Frameworks"
        platform_ldflags="-target $target_triple -isysroot $sdk_path -iframework $ios_support/System/Library/Frameworks"
        platform_link_args=(-target "$target_triple" -isysroot "$sdk_path" \
            -iframework "$ios_support/System/Library/Frameworks")
    else
        platform_cflags="-target $target_triple -isysroot $sdk_path $deployment_flag"
        platform_ldflags="-target $target_triple -isysroot $sdk_path $deployment_flag"
        platform_link_args=(-target "$target_triple" -isysroot "$sdk_path" "$deployment_flag")
    fi

    if [ -n "$nasm_executable" ]; then
        build_nasm_tool
        [ -x "$nasm_executable" ] ||
            die "isolated NASM is missing: $nasm_executable"
    fi
}

gmp_prefix_for_current_target() {
    printf '%s/gmp\n' "$(stage_dir "$target_name")"
}

nettle_prefix_for_current_target() {
    printf '%s/nettle\n' "$(stage_dir "$target_name")"
}

gnutls_prefix_for_current_target() {
    printf '%s/gnutls\n' "$(stage_dir "$target_name")"
}

ffmpeg_prefix_for_current_target() {
    printf '%s/ffmpeg\n' "$(stage_dir "$target_name")"
}

target_log_dir() {
    printf '%s/logs/%s\n' "$work_root" "$target_name"
}

record_dependency_configuration() {
    local dependency="$1"
    local build="$2"
    local output="$(metadata_dir)/slices/$target_name/dependencies/$dependency"
    [ -f "$build/config.log" ] ||
        die "missing $dependency configuration log for $target_name"
    [ -x "$build/config.status" ] ||
        die "missing $dependency config.status for $target_name"
    mkdir -p "$output"
    cp "$build/config.log" "$output/config.log"
    "$build/config.status" --config > "$output/configure-arguments.txt"
}

assert_static_archive_architecture() {
    local archive="$1"
    local actual
    actual="$(lipo -archs "$archive")"
    [ "$actual" = "$slice_arch" ] ||
        die "$(basename "$archive") has architecture '$actual', expected '$slice_arch'"
}

verify_gmp_pic_archive() {
    local archive="$(gmp_prefix_for_current_target)/lib/libgmp.a"
    local probe_dir="$(build_dir "$target_name")/gmp-pic-link-probe"
    local probe="$probe_dir/libgmp-pic-link-probe.dylib"
    local report="$(metadata_dir)/slices/$target_name/dependencies/gmp/pic-link-probe.txt"
    mkdir -p "$probe_dir" "$(dirname "$report")"
    "$clang_path" "${platform_link_args[@]}" -dynamiclib \
        -Wl,-force_load,"$archive" \
        -install_name @rpath/libgmp-pic-link-probe.dylib \
        -o "$probe.partial"
    mv "$probe.partial" "$probe"
    {
        printf 'archive_sha256=%s\n' "$(shasum -a 256 "$archive" | awk '{ print $1 }')"
        printf 'probe_sha256=%s\n' "$(shasum -a 256 "$probe" | awk '{ print $1 }')"
        printf 'link_mode=dynamiclib-force_load-entire-static-archive\n'
        vtool -show-build "$probe"
    } > "$report"
}

dependency_prefix() {
    case "$1" in
        gmp) gmp_prefix_for_current_target ;;
        nettle) nettle_prefix_for_current_target ;;
        gnutls) gnutls_prefix_for_current_target ;;
        *) die "unknown dependency: $1" ;;
    esac
}

dependency_output_hashes() {
    local dependency="$1"
    local prefix
    prefix="$(dependency_prefix "$dependency")"
    [ -d "$prefix" ] || die "$dependency output prefix is missing: $prefix"
    (
        cd "$prefix"
        find . -path './.irplayer-build' -prune -o -type f -print0 |
            LC_ALL=C sort -z | xargs -0 shasum -a 256
        while IFS= read -r path; do
            printf 'symlink %s %s\n' "${path#./}" "$(readlink "$path")"
        done < <(find . -path './.irplayer-build' -prune -o -type l -print | LC_ALL=C sort)
    )
}

dependency_build_input() {
    local dependency="$1"
    local sdk_settings="$sdk_path/SDKSettings.json"
    local source_archive source_hash source_version source build_guess
    local gmp_prefix nettle_prefix
    gmp_prefix="$(gmp_prefix_for_current_target)"
    nettle_prefix="$(nettle_prefix_for_current_target)"
    case "$dependency" in
        gmp)
            source_archive="$(downloads_dir)/gmp-$gmp_version.tar.xz"
            source_hash="$gmp_archive_sha256"
            source_version="$gmp_version"
            source="$(vendor_dir)/gmp-$gmp_version"
            ;;
        nettle)
            source_archive="$(downloads_dir)/nettle-$nettle_version.tar.gz"
            source_hash="$nettle_archive_sha256"
            source_version="$nettle_version"
            source="$(vendor_dir)/nettle-$nettle_version"
            ;;
        gnutls)
            source_archive="$(downloads_dir)/gnutls-$gnutls_version.tar.xz"
            source_hash="$gnutls_archive_sha256"
            source_version="$gnutls_version"
            source="$(vendor_dir)/gnutls-$gnutls_version"
            ;;
        *) die "unknown dependency: $dependency" ;;
    esac
    [ -f "$source_archive" ] || die "$dependency source archive is missing: $source_archive"
    [ "$(shasum -a 256 "$source_archive" | awk '{ print $1 }')" = "$source_hash" ] ||
        die "$dependency source archive no longer matches its pin"
    if [ "$dependency" = gnutls ]; then
        build_guess="$($source/build-aux/config.guess)"
    else
        build_guess="$($source/config.guess)"
    fi
    {
        printf 'dependency_recipe_schema=1\n'
        printf 'builder_script_sha256=%s\n' "$(shasum -a 256 "$script_dir/build-ffmpeg-6.1.6.sh" | awk '{ print $1 }')"
        printf 'dependency=%s\nversion=%s\nsource_sha256=%s\n' \
            "$dependency" "$source_version" "$source_hash"
        printf 'source_tree_sha256=%s\n' "$(source_tree_digest "$source")"
        printf 'target_name=%s\ntarget_triple=%s\nhost=%s\nbuild=%s\n' \
            "$target_name" "$target_triple" "$gmp_host" "$build_guess"
        printf 'sdk_name=%s\nsdk_path=%s\n' "$sdk_name" "$sdk_path"
        if [ -f "$sdk_settings" ]; then
            printf 'sdk_settings_sha256=%s\n' "$(shasum -a 256 "$sdk_settings" | awk '{ print $1 }')"
        else
            printf 'sdk_settings_sha256=unavailable\n'
        fi
        printf 'cc=%s\n' "$clang_path"
        "$clang_path" --version
        printf 'cxx=%s\nhost_cc=%s\nhost_sdk_path=%s\n' \
            "$clangxx_path" "$host_clang_path" "$host_sdk_path"
        printf 'ar=%s\nranlib=%s\nnm=%s\n' "$ar_path" "$ranlib_path" "$nm_path"
        printf 'platform_cflags=%s\nplatform_ldflags=%s\n' "$platform_cflags" "$platform_ldflags"
        case "$dependency" in
            gmp)
                printf '%s\n' \
                    'CFLAGS=-O2 -fstrict-aliasing -fPIC ${platform_cflags}' \
                    'configure=--disable-shared --enable-static --disable-cxx --enable-assembly --with-pic'
                ;;
            nettle)
                printf 'gmp_archive_sha256=%s\n' "$(shasum -a 256 "$gmp_prefix/lib/libgmp.a" | awk '{ print $1 }')"
                printf '%s\n' \
                    'CFLAGS=-O2 -fstrict-aliasing ${platform_cflags}' \
                    'CPP=${clang_path} -E ${platform_cflags}' \
                    'CPPFLAGS=-I${gmp_prefix}/include' \
                    'LDFLAGS=${platform_ldflags} -L${gmp_prefix}/lib' \
                    'LIBS=-lgmp' \
                    'configure=--disable-shared --enable-static --disable-documentation --disable-openssl'
                ;;
            gnutls)
                printf 'gmp_archive_sha256=%s\n' "$(shasum -a 256 "$gmp_prefix/lib/libgmp.a" | awk '{ print $1 }')"
                printf 'nettle_archive_sha256=%s\n' "$(shasum -a 256 "$nettle_prefix/lib/libnettle.a" | awk '{ print $1 }')"
                printf 'hogweed_archive_sha256=%s\n' "$(shasum -a 256 "$nettle_prefix/lib/libhogweed.a" | awk '{ print $1 }')"
                printf 'pkg_config_facade_sha256=%s\n' "$(shasum -a 256 "$isolated_pkg_config" | awk '{ print $1 }')"
                printf '%s\n' \
                    'CFLAGS=-O2 -fstrict-aliasing ${platform_cflags}' \
                    'CPP=${clang_path} -E ${platform_cflags}' \
                    'CPPFLAGS=-I${gmp_prefix}/include -I${nettle_prefix}/include' \
                    'LDFLAGS=${platform_ldflags} -L${nettle_prefix}/lib -L${gmp_prefix}/lib -liconv' \
                    'LIBS=-lhogweed -lnettle -lgmp -liconv' \
                    'configure=--disable-shared --enable-static --disable-doc --disable-tools --disable-tests --disable-nls --disable-cxx --disable-libdane --disable-ssl2-support --without-p11-kit --without-idn --without-zlib --without-brotli --without-zstd --with-included-libtasn1 --with-included-unistring --disable-rpath --enable-cross-guesses=conservative'
                ;;
        esac
    }
}

assert_current_dependency_fingerprint() {
    local dependency="$1"
    local marker_dir="$(dependency_prefix "$dependency")/.irplayer-build"
    local input="$marker_dir/build-input.txt"
    local fingerprint="$marker_dir/build-input.sha256"
    local outputs="$marker_dir/output-sha256sums.txt"
    local expected actual
    [ -f "$input" ] && [ -f "$fingerprint" ] && [ -f "$outputs" ] ||
        die "existing $dependency for $target_name has no complete input/output fingerprint; use a fresh isolated work root"
    actual="$(shasum -a 256 "$input" | awk '{ print $1 }')"
    [ "$actual" = "$(tr -d '\n' < "$fingerprint")" ] ||
        die "stored $dependency fingerprint is corrupt for $target_name; use a fresh isolated work root"
    expected="$(dependency_build_input "$dependency" | shasum -a 256 | awk '{ print $1 }')"
    [ "$actual" = "$expected" ] ||
        die "existing $dependency inputs do not match the current source, recipe, target, SDK, toolchain, or upstream archives; use a fresh isolated work root"
    actual="$(dependency_output_hashes "$dependency")"
    [ "$actual" = "$(cat "$outputs")" ] ||
        die "existing $dependency outputs do not match their recorded hashes; use a fresh isolated work root"
}

record_current_dependency_fingerprint() {
    local dependency="$1"
    local marker_dir="$(dependency_prefix "$dependency")/.irplayer-build"
    local metadata_output="$(metadata_dir)/slices/$target_name/dependencies/$dependency"
    mkdir -p "$marker_dir" "$metadata_output"
    dependency_build_input "$dependency" > "$marker_dir/build-input.txt.partial"
    mv "$marker_dir/build-input.txt.partial" "$marker_dir/build-input.txt"
    shasum -a 256 "$marker_dir/build-input.txt" | awk '{ print $1 }' > "$marker_dir/build-input.sha256"
    dependency_output_hashes "$dependency" > "$marker_dir/output-sha256sums.txt"
    cp "$marker_dir"/* "$metadata_output/"
}

build_gmp_for_current_target() {
    local prefix
    local build
    local source
    local common_cflags
    prefix="$(gmp_prefix_for_current_target)"
    build="$(build_dir "$target_name")/gmp"
    source="$(vendor_dir)/gmp-$gmp_version"
    common_cflags="-O2 -fstrict-aliasing -fPIC $platform_cflags"

    if [ -f "$prefix/lib/libgmp.a" ]; then
        assert_static_archive_architecture "$prefix/lib/libgmp.a"
        assert_current_dependency_fingerprint gmp
        verify_gmp_pic_archive
        record_dependency_configuration gmp "$build"
        log "reusing GMP $target_name"
        return
    fi

    mkdir -p "$build" "$(target_log_dir)" "$prefix"
    log "building GMP $gmp_version for $target_name"
    (
        cd "$build"
        env \
            CC="$clang_path" \
            CC_FOR_BUILD="$host_clang_path -isysroot $host_sdk_path" \
            AR="$ar_path" \
            RANLIB="$ranlib_path" \
            NM="$nm_path" \
            CFLAGS="$common_cflags" \
            LDFLAGS="$platform_ldflags" \
            "$source/configure" \
                --build="$("$source/config.guess")" \
                --host="$gmp_host" \
                --prefix="$prefix" \
                --disable-shared \
                --enable-static \
                --disable-cxx \
                --enable-assembly \
                --with-pic
        make -j"$jobs"
        make install
    ) 2>&1 | tee "$(target_log_dir)/gmp-build.log"
    [ -f "$prefix/lib/libgmp.a" ] || die "GMP archive was not installed"
    assert_static_archive_architecture "$prefix/lib/libgmp.a"
    verify_gmp_pic_archive
    record_current_dependency_fingerprint gmp
    record_dependency_configuration gmp "$build"
}

build_nettle_for_current_target() {
    local prefix="$(nettle_prefix_for_current_target)"
    local gmp_prefix="$(gmp_prefix_for_current_target)"
    local build="$(build_dir "$target_name")/nettle"
    local source="$(vendor_dir)/nettle-$nettle_version"
    local common_cflags="-O2 -fstrict-aliasing $platform_cflags"

    if [ -f "$prefix/lib/libnettle.a" ] && [ -f "$prefix/lib/libhogweed.a" ]; then
        assert_static_archive_architecture "$prefix/lib/libnettle.a"
        assert_static_archive_architecture "$prefix/lib/libhogweed.a"
        assert_current_dependency_fingerprint nettle
        record_dependency_configuration nettle "$build"
        log "reusing Nettle $target_name"
        return
    fi
    [ ! -e "$prefix/lib" ] ||
        die "partial Nettle install exists for $target_name; use a fresh isolated work root"

    mkdir -p "$build" "$(target_log_dir)" "$prefix"
    log "building Nettle $nettle_version for $target_name"
    (
        cd "$build"
        env \
            CC="$clang_path" \
            CPP="$clang_path -E $platform_cflags" \
            AR="$ar_path" \
            RANLIB="$ranlib_path" \
            NM="$nm_path" \
            CFLAGS="$common_cflags" \
            CPPFLAGS="-I$gmp_prefix/include" \
            LDFLAGS="$platform_ldflags -L$gmp_prefix/lib" \
            LIBS="-lgmp" \
            "$source/configure" \
                --build="$("$source/config.guess")" \
                --host="$gmp_host" \
                --prefix="$prefix" \
                --disable-shared \
                --enable-static \
                --disable-documentation \
                --disable-openssl
        make -j"$jobs"
        make install
    ) 2>&1 | tee "$(target_log_dir)/nettle-build.log"
    [ -f "$prefix/lib/libnettle.a" ] || die "Nettle archive was not installed"
    [ -f "$prefix/lib/libhogweed.a" ] || die "Hogweed archive was not installed"
    assert_static_archive_architecture "$prefix/lib/libnettle.a"
    assert_static_archive_architecture "$prefix/lib/libhogweed.a"
    record_current_dependency_fingerprint nettle
    record_dependency_configuration nettle "$build"
}

build_gnutls_for_current_target() {
    local prefix="$(gnutls_prefix_for_current_target)"
    local gmp_prefix="$(gmp_prefix_for_current_target)"
    local nettle_prefix="$(nettle_prefix_for_current_target)"
    local build="$(build_dir "$target_name")/gnutls"
    local source="$(vendor_dir)/gnutls-$gnutls_version"
    local common_cflags="-O2 -fstrict-aliasing $platform_cflags"
    local nettle_libs="-L$nettle_prefix/lib -lnettle -L$gmp_prefix/lib -lgmp"
    local hogweed_libs="-L$nettle_prefix/lib -lhogweed -lnettle -L$gmp_prefix/lib -lgmp"

    if [ -f "$prefix/lib/libgnutls.a" ]; then
        assert_static_archive_architecture "$prefix/lib/libgnutls.a"
        assert_current_dependency_fingerprint gnutls
        record_dependency_configuration gnutls "$build"
        log "reusing GnuTLS $target_name"
        return
    fi
    [ ! -e "$prefix/lib" ] ||
        die "partial GnuTLS install exists for $target_name; use a fresh isolated work root"
    [ -x "$isolated_pkg_config" ] ||
        die "isolated pkg-config facade is missing or not executable: $isolated_pkg_config"

    mkdir -p "$build" "$(target_log_dir)" "$prefix"
    log "building GnuTLS $gnutls_version for $target_name"
    (
        cd "$build"
        env \
            CC="$clang_path" \
            CXX="$clangxx_path $platform_cflags" \
            CPP="$clang_path -E $platform_cflags" \
            AR="$ar_path" \
            RANLIB="$ranlib_path" \
            NM="$nm_path" \
            PKG_CONFIG="$isolated_pkg_config" \
            IRPLAYER_PKG_CONFIG_GMP_PREFIX="$gmp_prefix" \
            IRPLAYER_PKG_CONFIG_NETTLE_PREFIX="$nettle_prefix" \
            IRPLAYER_PKG_CONFIG_GNUTLS_PREFIX="$prefix" \
            CFLAGS="$common_cflags" \
            CPPFLAGS="-I$gmp_prefix/include -I$nettle_prefix/include" \
            LDFLAGS="$platform_ldflags -L$nettle_prefix/lib -L$gmp_prefix/lib -liconv" \
            LIBS="-lhogweed -lnettle -lgmp -liconv" \
            NETTLE_CFLAGS="-I$nettle_prefix/include" \
            NETTLE_LIBS="$nettle_libs" \
            HOGWEED_CFLAGS="-I$nettle_prefix/include" \
            HOGWEED_LIBS="$hogweed_libs" \
            GMP_CFLAGS="-I$gmp_prefix/include" \
            GMP_LIBS="-L$gmp_prefix/lib -lgmp" \
            "$source/configure" \
                --build="$("$source/build-aux/config.guess")" \
                --host="$gmp_host" \
                --prefix="$prefix" \
                --disable-shared \
                --enable-static \
                --disable-doc \
                --disable-tools \
                --disable-tests \
                --disable-nls \
                --disable-cxx \
                --disable-libdane \
                --disable-ssl2-support \
                --without-p11-kit \
                --without-idn \
                --without-zlib \
                --without-brotli \
                --without-zstd \
                --with-included-libtasn1 \
                --with-included-unistring \
                --disable-rpath \
                --enable-cross-guesses=conservative
        make -j"$jobs"
        make install
    ) 2>&1 | tee "$(target_log_dir)/gnutls-build.log"
    [ -f "$prefix/lib/libgnutls.a" ] || die "GnuTLS archive was not installed"
    assert_static_archive_architecture "$prefix/lib/libgnutls.a"
    record_current_dependency_fingerprint gnutls
    record_dependency_configuration gnutls "$build"
}

base_ffmpeg_flags=(
    --enable-version3
    --target-os=darwin
    --enable-cross-compile
    --enable-pic
    --enable-inline-asm
    --enable-optimizations
    --enable-swscale
    --enable-shared
    --disable-static
    --install-name-dir=@rpath
    --enable-pthreads
    --disable-autodetect
    --disable-v4l2-m2m
    --disable-outdev=v4l2
    --disable-outdev=fbdev
    --disable-indev=v4l2
    --disable-indev=fbdev
    --enable-small
    --disable-xmm-clobber-test
    --disable-debug
    --disable-neon-clobber-test
    --disable-programs
    --disable-postproc
    --disable-doc
    --disable-htmlpages
    --disable-manpages
    --disable-podpages
    --disable-txtpages
    --disable-sndio
    --disable-schannel
    --disable-securetransport
    --enable-gnutls
    --disable-openssl
    --disable-mbedtls
    --disable-libtls
    --disable-xlib
    --disable-cuda
    --disable-cuvid
    --disable-nvenc
    --disable-vaapi
    --disable-vdpau
    --disable-alsa
    --enable-gmp
    --disable-sdl2
    --enable-zlib
    --enable-audiotoolbox
    --disable-outdev=audiotoolbox
    --enable-bzlib
    --enable-videotoolbox
    # scale_vt first ships in FFmpeg 6.1 and calls iOS 16-only
    # VTPixelTransferSession APIs without an availability guard. It is absent
    # from the shipped n6.0 bundle; retain iOS 15 support by excluding only
    # this newly introduced filter, not VideoToolbox or existing scalers.
    --disable-filter=scale_vt
    --enable-avfoundation
    --enable-iconv
    --disable-coreimage
    --disable-appkit
    --disable-opencl
    --disable-opengl
)

ffmpeg_fingerprint_path() {
    printf '%s/ffmpeg-build-fingerprint.sha256\n' "$(stage_dir "$1")"
}

ffmpeg_patch_manifest_path() {
    printf '%s/ffmpeg-patch-manifest.sha256\n' "$(stage_dir "$1")"
}

ffmpeg_patch_diff_path() {
    printf '%s/ffmpeg-patch-diff.sha256\n' "$(stage_dir "$1")"
}

assert_all_installed_libraries() {
    local prefix="$1"
    local library
    for library in "${libraries[@]}"; do
        find_installed_dylib "$prefix" "$library" >/dev/null
    done
}

target_build_input() {
    local sdk_settings="$sdk_path/SDKSettings.json"
    local flag
    local gmp_archive="$(gmp_prefix_for_current_target)/lib/libgmp.a"
    local nettle_archive="$(nettle_prefix_for_current_target)/lib/libnettle.a"
    local hogweed_archive="$(nettle_prefix_for_current_target)/lib/libhogweed.a"
    local gnutls_archive="$(gnutls_prefix_for_current_target)/lib/libgnutls.a"
    [ -f "$gmp_archive" ] || die "GMP archive is missing for $target_name: $gmp_archive"
    [ -f "$nettle_archive" ] || die "Nettle archive is missing for $target_name: $nettle_archive"
    [ -f "$hogweed_archive" ] || die "Hogweed archive is missing for $target_name: $hogweed_archive"
    [ -f "$gnutls_archive" ] || die "GnuTLS archive is missing for $target_name: $gnutls_archive"
    {
        printf 'ffmpeg_tag=%s\n' "$ffmpeg_tag"
        printf 'ffmpeg_commit=%s\n' "$ffmpeg_commit"
        printf 'ffmpeg_tree=%s\n' "$(git -C "$(source_dir)" rev-parse "$ffmpeg_commit^{tree}")"
        printf 'patch_manifest_sha256=%s\n' "$(current_patch_manifest_hash)"
        printf 'gmp_version=%s\n' "$gmp_version"
        printf 'gmp_archive_sha256=%s\n' "$(shasum -a 256 "$gmp_archive" | awk '{ print $1 }')"
        printf 'nettle_version=%s\n' "$nettle_version"
        printf 'nettle_archive_sha256=%s\n' "$(shasum -a 256 "$nettle_archive" | awk '{ print $1 }')"
        printf 'hogweed_archive_sha256=%s\n' "$(shasum -a 256 "$hogweed_archive" | awk '{ print $1 }')"
        printf 'gnutls_version=%s\n' "$gnutls_version"
        printf 'gnutls_archive_sha256=%s\n' "$(shasum -a 256 "$gnutls_archive" | awk '{ print $1 }')"
        printf 'pkg_config_facade_sha256=%s\n' "$(shasum -a 256 "$isolated_pkg_config" | awk '{ print $1 }')"
        printf 'target_name=%s\n' "$target_name"
        printf 'target_triple=%s\n' "$target_triple"
        printf 'sdk_name=%s\n' "$sdk_name"
        printf 'sdk_path=%s\n' "$sdk_path"
        if [ -f "$sdk_settings" ]; then
            printf 'sdk_settings_sha256=%s\n' "$(shasum -a 256 "$sdk_settings" | awk '{ print $1 }')"
        else
            printf 'sdk_settings_sha256=unavailable\n'
        fi
        printf 'cc=%s\n' "$clang_path"
        "$clang_path" --version
        printf 'ar=%s\nranlib=%s\nnm=%s\nstrip=%s\n' \
            "$ar_path" "$ranlib_path" "$nm_path" "$strip_path"
        printf 'platform_cflags=%s\nplatform_ldflags=%s\n' \
            "$platform_cflags" "$platform_ldflags"
        printf 'nasm=%s\n' "${nasm_executable:-not-used}"
        if [ -n "${nasm_executable:-}" ]; then
            "$nasm_executable" -v
        fi
        printf '[target_flags]\n'
        for flag in "${ffmpeg_asm_flags[@]}"; do
            printf '%s\n' "$flag"
        done
        printf '[base_flags]\n'
        for flag in "${base_ffmpeg_flags[@]}"; do
            printf '%s\n' "$flag"
        done
    }
}

current_ffmpeg_fingerprint() {
    target_build_input | shasum -a 256 | awk '{ print $1 }'
}

assert_current_ffmpeg_fingerprint() {
    local target="$1"
    local fingerprint_file
    local expected
    local actual
    fingerprint_file="$(ffmpeg_fingerprint_path "$target")"
    [ -f "$fingerprint_file" ] ||
        die "built $target has no fingerprint; use a fresh isolated work root"
    expected="$(current_ffmpeg_fingerprint)"
    actual="$(tr -d '\n' < "$fingerprint_file")"
    [ "$actual" = "$expected" ] ||
        die "built $target does not match the current source, patch, dependency, or toolchain fingerprint; use a fresh isolated work root"
}

record_current_ffmpeg_fingerprint() {
    local target="$1"
    local slice_metadata
    local input
    local temporary_input
    local fingerprint
    slice_metadata="$(metadata_dir)/slices/$target"
    input="$slice_metadata/build-input.txt"
    temporary_input="$input.partial"
    mkdir -p "$slice_metadata" "$(stage_dir "$target")"
    target_build_input > "$temporary_input"
    mv "$temporary_input" "$input"
    fingerprint="$(shasum -a 256 "$input" | awk '{ print $1 }')"
    printf '%s\n' "$fingerprint" > "$(ffmpeg_fingerprint_path "$target")"
}

apply_transport_patches() {
    local worktree="$1"
    local manifest_hash
    local manifest_marker
    local diff_marker
    local patch
    local actual_diff
    manifest_hash="$(current_patch_manifest_hash)"
    manifest_marker="$(ffmpeg_patch_manifest_path "$target_name")"
    diff_marker="$(ffmpeg_patch_diff_path "$target_name")"

    if [ -f "$manifest_marker" ]; then
        [ "$(tr -d '\n' < "$manifest_marker")" = "$manifest_hash" ] ||
            die "existing $target_name worktree uses a different transport patch set"
        [ -f "$diff_marker" ] ||
            die "existing $target_name worktree lacks its patch-diff fingerprint"
        [ -z "$(git -C "$worktree" diff --no-ext-diff)" ] ||
            die "existing $target_name worktree has unstaged changes"
        [ -z "$(git -C "$worktree" ls-files --others --exclude-standard)" ] ||
            die "existing $target_name worktree has untracked build output"
        actual_diff="$(git -C "$worktree" diff --cached --binary --no-ext-diff | shasum -a 256 | awk '{ print $1 }')"
        [ "$(tr -d '\n' < "$diff_marker")" = "$actual_diff" ] ||
            die "existing $target_name worktree patch diff does not match its recorded fingerprint"
        return
    fi

    [ -z "$(git -C "$worktree" status --porcelain)" ] ||
        die "existing $target_name worktree is modified without a validated patch manifest"
    assert_recorded_transport_patch_snapshot
    while IFS= read -r patch; do
        log "applying $(basename "$patch") to $target_name"
        git -C "$worktree" apply --index --check "$patch"
        git -C "$worktree" apply --index --whitespace=error-all "$patch"
    done < <(list_recorded_transport_patches)
    git -C "$worktree" diff --cached --check
    mkdir -p "$(stage_dir "$target_name")"
    printf '%s\n' "$manifest_hash" > "$manifest_marker"
    git -C "$worktree" diff --cached --binary --no-ext-diff | shasum -a 256 | awk '{ print $1 }' \
        > "$diff_marker"
}

assert_feature_enabled() {
    local feature="$1"
    shift
    local config
    for config in "$@"; do
        grep -F "#define $feature 1" "$config" >/dev/null && return
    done
    die "required FFmpeg feature missing from $target_name: $feature"
}

assert_feature_disabled() {
    local feature="$1"
    shift
    local config
    for config in "$@"; do
        grep -F "#define $feature 0" "$config" >/dev/null && return
    done
    die "required FFmpeg feature still enabled in $target_name: $feature"
}

verify_configured_features() {
    local config="$1"
    local components="$2"
    [ -f "$config" ] || die "missing FFmpeg config.h for $target_name"
    [ -f "$components" ] || die "missing FFmpeg config_components.h for $target_name"
    local feature
    for feature in \
        CONFIG_GMP \
        CONFIG_GNUTLS \
        CONFIG_TLS_PROTOCOL \
        CONFIG_HTTP_PROTOCOL \
        CONFIG_HTTPS_PROTOCOL \
        CONFIG_HLS_DEMUXER \
        CONFIG_RTSP_DEMUXER \
        CONFIG_RTMP_PROTOCOL \
        CONFIG_RTMPE_PROTOCOL \
        CONFIG_FFRTMPCRYPT_PROTOCOL \
        CONFIG_FILE_PROTOCOL \
        CONFIG_AUDIOTOOLBOX \
        CONFIG_VIDEOTOOLBOX \
        CONFIG_AVFOUNDATION_INDEV; do
        assert_feature_enabled "$feature" "$config" "$components"
    done
    for feature in \
        CONFIG_SECURETRANSPORT \
        CONFIG_OPENSSL \
        CONFIG_MBEDTLS \
        CONFIG_LIBTLS \
        CONFIG_SCALE_VT_FILTER; do
        assert_feature_disabled "$feature" "$config" "$components"
    done
}

find_installed_dylib() {
    local prefix="$1"
    local library="$2"
    local candidate
    for candidate in "$prefix/lib/$library".*.dylib; do
        [ -f "$candidate" ] && {
            printf '%s\n' "$candidate"
            return
        }
    done
    die "missing installed dylib for $library in $prefix/lib"
}

build_ffmpeg_for_current_target() {
    local prefix
    local worktree
    local gmp_prefix
    local nettle_prefix
    local gnutls_prefix
    local source
    local config
    local components
    local source_date_epoch
    local common_cflags
    local common_ldflags
    local assembler
    local configure_args=()
    prefix="$(ffmpeg_prefix_for_current_target)"
    worktree="$(build_dir "$target_name")/ffmpeg"
    gmp_prefix="$(gmp_prefix_for_current_target)"
    nettle_prefix="$(nettle_prefix_for_current_target)"
    gnutls_prefix="$(gnutls_prefix_for_current_target)"
    source="$(source_dir)"
    config="$worktree/config.h"
    components="$worktree/config_components.h"
    source_date_epoch="$(git -C "$source" show -s --format=%ct "$ffmpeg_commit")"
    common_cflags="-O2 -Wno-unused-function -Wno-deprecated-declarations -fstrict-aliasing $platform_cflags -I$gmp_prefix/include -I$nettle_prefix/include -I$gnutls_prefix/include"
    # iOS and Catalyst ship iconv in libiconv rather than libSystem. With
    # --disable-autodetect FFmpeg otherwise probes it as libc_iconv and omits
    # the necessary link dependency, leaving libavcodec unresolved.
    common_ldflags="$platform_ldflags -L$gnutls_prefix/lib -L$nettle_prefix/lib -L$gmp_prefix/lib -liconv -Wl,-headerpad_max_install_names"
    assembler="$clang_path $platform_cflags"

    if [ -f "$prefix/lib/libavformat.60.dylib" ]; then
        assert_all_installed_libraries "$prefix"
        assert_current_ffmpeg_fingerprint "$target_name"
        log "reusing FFmpeg $target_name"
        return
    fi

    [ ! -e "$prefix/lib" ] ||
        die "partial FFmpeg install exists for $target_name; use a fresh isolated work root"

    mkdir -p "$(build_dir "$target_name")" "$(target_log_dir)" "$prefix"
    if [ ! -e "$worktree" ]; then
        git -C "$source" worktree add --detach "$worktree" "$ffmpeg_commit"
    fi
    [ "$(git -C "$worktree" rev-parse HEAD)" = "$ffmpeg_commit" ] ||
        die "FFmpeg worktree is not pinned: $worktree"
    apply_transport_patches "$worktree"

    log "configuring FFmpeg $ffmpeg_tag for $target_name"
    (
        cd "$worktree"
        export LC_ALL=C
        export TZ=UTC
        export SOURCE_DATE_EPOCH="$source_date_epoch"
        export ZERO_AR_DATE=1
        export PKG_CONFIG="$isolated_pkg_config"
        export IRPLAYER_PKG_CONFIG_GMP_PREFIX="$gmp_prefix"
        export IRPLAYER_PKG_CONFIG_NETTLE_PREFIX="$nettle_prefix"
        export IRPLAYER_PKG_CONFIG_GNUTLS_PREFIX="$gnutls_prefix"
        configure_args=( \
            --prefix="$prefix" \
            --arch="$ffmpeg_arch" \
            --cpu="$ffmpeg_cpu" \
            --sysroot="$sdk_path" \
            --cc="$clang_path" \
            --cxx="$clangxx_path" \
            --as="$assembler" \
            --ar="$ar_path" \
            --ranlib="$ranlib_path" \
            --strip="$strip_path" \
            --nm="$nm_path" \
            --pkg-config="$isolated_pkg_config" \
            --extra-cflags="$common_cflags" \
            --extra-ldflags="$common_ldflags" \
            "${ffmpeg_asm_flags[@]}" \
        )
        if [ -n "${nasm_executable:-}" ]; then
            configure_args+=(--x86asmexe="$nasm_executable")
        fi
        configure_args+=("${base_ffmpeg_flags[@]}")
        ./configure "${configure_args[@]}"
        verify_configured_features "$config" "$components"
        make -j"$jobs"
        make install
    ) 2>&1 | tee "$(target_log_dir)/ffmpeg-build.log"

    mkdir -p "$(metadata_dir)/slices/$target_name"
    cp "$worktree/config.h" "$(metadata_dir)/slices/$target_name/config.h"
    cp "$worktree/config_components.h" \
        "$(metadata_dir)/slices/$target_name/config_components.h"
    cp "$worktree/ffbuild/config.mak" "$(metadata_dir)/slices/$target_name/config.mak"
    cp "$worktree/ffbuild/config.sh" "$(metadata_dir)/slices/$target_name/config.sh"
    cp "$worktree/ffbuild/config.log" "$(metadata_dir)/slices/$target_name/config.log"
    shasum -a 256 "$prefix"/lib/*.dylib \
        > "$(metadata_dir)/slices/$target_name/dylib-sha256sums.txt"
    record_current_ffmpeg_fingerprint "$target_name"
}

build_target() {
    configure_target "$1"
    build_gmp_for_current_target
    build_nettle_for_current_target
    build_gnutls_for_current_target
    build_ffmpeg_for_current_target
}

stage_exists() {
    local target="$1"
    [ -f "$(stage_dir "$target")/ffmpeg/lib/libavformat.60.dylib" ]
}

assert_stage_exists() {
    local target
    for target in "$@"; do
        stage_exists "$target" ||
            die "missing built target slice: $target; run build first"
        configure_target "$target"
        assert_all_installed_libraries "$(stage_dir "$target")/ffmpeg"
        assert_current_ffmpeg_fingerprint "$target"
    done
}

target_library_path() {
    local target="$1"
    local library="$2"
    find_installed_dylib "$(stage_dir "$target")/ffmpeg" "$library"
}

target_headers_path() {
    local target="$1"
    local library="$2"
    printf '%s/ffmpeg/include/%s\n' "$(stage_dir "$target")" "$library"
}

write_framework_info_plist() {
    local plist="$1"
    local library="$2"
    local family="$3"
    local platform
    local minimum_key
    case "$family" in
        ios-device)
            platform=iPhoneOS
            minimum_key=MinimumOSVersion
            ;;
        ios-simulator)
            platform=iPhoneSimulator
            minimum_key=MinimumOSVersion
            ;;
        maccatalyst)
            platform=MacOSX
            minimum_key=LSMinimumSystemVersion
            ;;
        *) die "unknown framework platform family: $family" ;;
    esac
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$library</string>
    <key>CFBundleIdentifier</key>
    <string>org.irplayer.ffmpeg.n6_1_6.$library</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$library</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>6.1.6</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$platform</string>
    </array>
    <key>CFBundleVersion</key>
    <string>6.1.6</string>
    <key>$minimum_key</key>
    <string>15.0</string>
    <key>NSPrincipalClass</key>
    <string></string>
EOF
    cat >> "$plist" <<'EOF'
</dict>
</plist>
EOF
}

patch_framework_install_names() {
    local binary="$1"
    local own_library="$2"
    local library
    install_name_tool -id "@rpath/$own_library.framework/$own_library" "$binary"

    for library in "${libraries[@]}"; do
        local existing
        existing="$(otool -L "$binary" | awk -v lib="$library" '
            NR > 1 && $1 ~ ("@rpath/" lib "\\.[0-9]+\\.dylib") { print $1; exit }
        ')"
        if [ -n "$existing" ]; then
            install_name_tool -change "$existing" \
                "@rpath/$library.framework/$library" "$binary"
        fi
    done
}

assert_compatible_headers() {
    local library="$1"
    shift
    local first_target="$1"
    local first_header
    first_header="$(target_headers_path "$first_target" "$library")"
    [ -d "$first_header" ] ||
        die "missing installed public headers: $first_header"
    shift
    local target
    for target in "$@"; do
        local header
        header="$(target_headers_path "$target" "$library")"
        [ -d "$header" ] || die "missing installed public headers: $header"
        if [ "$library" = libavutil ]; then
            cmp -s "$first_header/avconfig.h" "$header/avconfig.h" ||
                die "libavutil avconfig.h differs between $first_target and $target"
        fi
    done
}

make_flat_framework() {
    local output="$1"
    local library="$2"
    local family="$3"
    shift 3
    local targets=("$@")
    local first_target="${targets[0]}"
    local headers
    local inputs=()
    local target
    assert_compatible_headers "$library" "${targets[@]}"
    for target in "${targets[@]}"; do
        inputs+=("$(target_library_path "$target" "$library")")
    done
    mkdir -p "$output/Headers"
    headers="$(target_headers_path "$first_target" "$library")"
    ditto "$headers" "$output/Headers"
    lipo -create "${inputs[@]}" -output "$output/$library"
    write_framework_info_plist "$output/Info.plist" "$library" "$family"
    patch_framework_install_names "$output/$library" "$library"
    codesign --force --sign - --timestamp=none "$output"
    codesign --verify --deep --strict "$output"
}

make_versioned_framework() {
    local output="$1"
    local library="$2"
    local family="$3"
    shift 3
    local targets=("$@")
    local first_target="${targets[0]}"
    local version_dir="$output/Versions/A"
    local headers
    local inputs=()
    local target
    assert_compatible_headers "$library" "${targets[@]}"
    for target in "${targets[@]}"; do
        inputs+=("$(target_library_path "$target" "$library")")
    done
    mkdir -p "$version_dir/Headers" "$version_dir/Resources"
    headers="$(target_headers_path "$first_target" "$library")"
    ditto "$headers" "$version_dir/Headers"
    lipo -create "${inputs[@]}" -output "$version_dir/$library"
    write_framework_info_plist "$version_dir/Resources/Info.plist" "$library" "$family"
    ln -s A "$output/Versions/Current"
    ln -s Versions/Current/Headers "$output/Headers"
    ln -s Versions/Current/Resources "$output/Resources"
    ln -s Versions/Current/$library "$output/$library"
    patch_framework_install_names "$version_dir/$library" "$library"
    codesign --force --sign - --timestamp=none "$output"
    codesign --verify --deep --strict "$output"
}

make_frameworks_for_family() {
    local package_work="$1"
    local family="$2"
    shift 2
    local targets=("$@")
    local framework_root="$package_work/frameworks/$family"
    local library
    mkdir -p "$framework_root"
    for library in "${libraries[@]}"; do
        local framework="$framework_root/$library.framework"
        if [ "$family" = maccatalyst ]; then
            make_versioned_framework "$framework" "$library" "$family" "${targets[@]}"
        else
            make_flat_framework "$framework" "$library" "$family" "${targets[@]}"
        fi
    done
}

make_package_metadata() {
    local package="$1"
    local metadata="$package/metadata"
    local patch_hash
    local patch_snapshot
    mkdir -p "$metadata"
    cp "$(metadata_dir)/source-and-toolchain.txt" "$metadata/"
    cp "$(metadata_dir)/license-sha256sums.txt" "$metadata/"
    ditto "$(metadata_dir)/licenses" "$metadata/licenses"
    cp "$(patch_manifest_path)" "$metadata/patches.manifest"
    cp "$(patch_manifest_sha_path)" "$metadata/patches.manifest.sha256"
    patch_hash="$(current_patch_manifest_hash)"
    patch_snapshot="$(metadata_dir)/patches/$patch_hash"
    [ -d "$patch_snapshot" ] ||
        die "missing immutable transport patch snapshot: $patch_snapshot"
    mkdir -p "$metadata/patches"
    ditto "$patch_snapshot" "$metadata/patches/$patch_hash"
    find "$(metadata_dir)/slices" -type f -print | LC_ALL=C sort | while read -r file; do
        local_relative="${file#$(metadata_dir)/}"
        mkdir -p "$metadata/$(dirname "$local_relative")"
        cp "$file" "$metadata/$local_relative"
    done
}

write_package_artifact_checksums() {
    local package="$1"
    local checksums="$package/metadata/artifact-sha256sums.txt"
    local temporary="$(metadata_dir)/$(basename "$package").artifact-sha256sums.$$.partial"
    [ -d "$package/metadata" ] || die "missing package metadata: $package/metadata"
    [ ! -e "$checksums" ] ||
        die "package checksum manifest already exists: $checksums"
    [ ! -e "$temporary" ] || die "temporary package checksum manifest exists: $temporary"
    (
        cd "$package"
        find . -type f ! -path './metadata/artifact-sha256sums.txt' -print | \
            LC_ALL=C sort | while IFS= read -r file; do
                shasum -a 256 "$file"
            done
    ) > "$temporary"
    mv "$temporary" "$checksums"
    (
        cd "$package"
        shasum -a 256 -c "metadata/artifact-sha256sums.txt" >/dev/null
    ) || die "new package checksum manifest does not verify"
}

verify_package_artifact_checksums() {
    local package="$1"
    local checksums="$package/metadata/artifact-sha256sums.txt"
    [ -f "$checksums" ] || die "missing package checksum manifest: $checksums"
    (
        cd "$package"
        shasum -a 256 -c "metadata/artifact-sha256sums.txt" >/dev/null
    ) || die "package artifact checksum verification failed"
}

package_frameworks() {
    local package="$1"
    shift
    local families=("$@")
    [ ! -e "$package" ] ||
        die "package output already exists; use a new work root or remove it explicitly: $package"

    local package_work="$work_root/package/$(basename "$package")"
    [ ! -e "$package_work" ] ||
        die "package workspace already exists; use a new work root or remove it explicitly: $package_work"
    mkdir -p "$package_work"

    local family
    for family in "${families[@]}"; do
        case "$family" in
            ios-device)
                make_frameworks_for_family "$package_work" "$family" ios-device-arm64
                ;;
            ios-simulator)
                if stage_exists ios-simulator-x86_64; then
                    make_frameworks_for_family "$package_work" "$family" \
                        ios-simulator-arm64 ios-simulator-x86_64
                else
                    make_frameworks_for_family "$package_work" "$family" ios-simulator-arm64
                fi
                ;;
            maccatalyst)
                make_frameworks_for_family "$package_work" "$family" \
                    maccatalyst-arm64 maccatalyst-x86_64
                ;;
            *) die "unsupported package family: $family" ;;
        esac
    done

    mkdir -p "$package/xcframeworks"
    local library
    for library in "${libraries[@]}"; do
        local command=(xcodebuild -create-xcframework)
        for family in "${families[@]}"; do
            command+=( -framework "$package_work/frameworks/$family/$library.framework" )
        done
        command+=( -output "$package/xcframeworks/$library.xcframework" )
        "${command[@]}"
    done
}

framework_binary() {
    local xcframework="$1"
    local library="$2"
    local family="$3"
    local pattern
    case "$family" in
        ios-device) pattern='*/ios-arm64/*' ;;
        ios-simulator) pattern='*simulator/*' ;;
        maccatalyst) pattern='*maccatalyst/*' ;;
        *) die "unknown framework family: $family" ;;
    esac
    find "$xcframework" -type f -name "$library" -path "$pattern" | head -n 1
}

framework_search_path() {
    local xcframework="$1"
    local library="$2"
    local family="$3"
    local binary
    binary="$(framework_binary "$xcframework" "$library" "$family")"
    [ -n "$binary" ] || die "missing $library framework for $family"
    local directory
    directory="$(dirname "$binary")"
    while [ "$directory" != / ]; do
        case "$directory" in
            *.framework)
                dirname "$directory"
                return
                ;;
        esac
        directory="$(dirname "$directory")"
    done
    die "could not find framework bundle for $binary"
}

sorted_architectures() {
    lipo -archs "$1" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

verify_framework_binary() {
    local binary="$1"
    local library="$2"
    local expected_archs="$3"
    local actual_archs
    actual_archs="$(sorted_architectures "$binary")"
    [ "$actual_archs" = "$expected_archs" ] ||
        die "$library has architectures '$actual_archs', expected '$expected_archs'"
    otool -D "$binary" | grep -F "@rpath/$library.framework/$library" >/dev/null ||
        die "$library has an unexpected install name"
}

verify_transport_binary() {
    local binary="$1"
    if [ "$patch_mode" != none ]; then
        [ -x "$apple_framework_verifier" ] ||
            die "Apple framework dependency verifier is missing or not executable: $apple_framework_verifier"
        "$apple_framework_verifier" "$binary" Security Security ||
            die "libavformat is missing Security.framework"
        "$apple_framework_verifier" "$binary" CoreFoundation CoreFoundation ||
            die "libavformat is missing CoreFoundation.framework"
        nm -u "$binary" | grep -F '_SecTrustEvaluateWithError' >/dev/null ||
            die "libavformat is missing the SecTrust verification path"
    fi
    strings "$binary" | grep -F -- '--enable-gnutls' >/dev/null ||
        die "libavformat does not record GnuTLS enabled"
    strings "$binary" | grep -F -- '--disable-securetransport' >/dev/null ||
        die "libavformat does not record SecureTransport disabled"
    strings "$binary" | grep -F '_gnutls_global_init' >/dev/null ||
        die "libavformat does not contain the statically linked GnuTLS code"
    strings "$binary" | grep -F 'Detected downgrade to TLS 1.2 from TLS 1.3' >/dev/null ||
        die "libavformat does not contain GnuTLS TLS 1.3 support"
    if otool -L "$binary" | grep -E '/lib(gnutls|nettle|hogweed|gmp)[^/]*\.dylib' >/dev/null; then
        die "libavformat unexpectedly depends on a dynamic GnuTLS dependency"
    fi
}

verify_iconv_binary() {
    local binary="$1"
    otool -L "$binary" | grep -F '/usr/lib/libiconv.2.dylib' >/dev/null ||
        die "libavcodec is missing the required libiconv dependency"
}

verify_public_wrapper_link() {
    local package="$1"
    local family="$2"
    local target
    local sdk
    local catalyst_flags=()
    case "$family" in
        ios-device)
            target=arm64-apple-ios15.0
            sdk=iphoneos
            ;;
        ios-simulator)
            target=arm64-apple-ios15.0-simulator
            sdk=iphonesimulator
            ;;
        maccatalyst)
            target=arm64-apple-ios15.0-macabi
            sdk=macosx
            ;;
        *) die "unknown wrapper verification family: $family" ;;
    esac

    local clang
    local sdk_path
    clang="$(xcrun --sdk "$sdk" --find clang)"
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    if [ "$family" = maccatalyst ]; then
        catalyst_flags=( \
            -isystem "$sdk_path/System/iOSSupport/usr/include" \
            -iframework "$sdk_path/System/iOSSupport/System/Library/Frameworks" \
        )
    fi
    local flags=()
    local library
    for library in libavcodec libavformat libavutil libswresample libswscale; do
        flags+=( -F "$(framework_search_path "$package/xcframeworks/$library.xcframework" "$library" "$family")" )
    done
    # Keep verification output outside the package. A later `verify` action
    # must not mutate a package already covered by artifact checksums.
    local probe_root="$work_root/verification/$(basename "$package")/$family"
    mkdir -p "$probe_root"
    "$clang" -fobjc-arc -fmodules -dynamiclib \
        -target "$target" \
        -isysroot "$sdk_path" \
        "${catalyst_flags[@]+"${catalyst_flags[@]}"}" \
        -I "$repository_root/Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/include" \
        "${flags[@]}" \
        "$repository_root/Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/IRFFMpeg.m" \
        -framework Foundation \
        -framework libavcodec \
        -framework libavformat \
        -framework libavutil \
        -framework libswresample \
        -framework libswscale \
        -o "$probe_root/libIRFFMpegPrototypeProbe.dylib"
}

verify_package() {
    local package="$1"
    local minimal="$2"
    [ -d "$package/xcframeworks" ] ||
        die "package does not exist: $package"
    local family
    local library
    local expected_archs
    local families=(ios-device ios-simulator)
    if [ "$minimal" = no ]; then
        families+=(maccatalyst)
    fi

    for library in "${libraries[@]}"; do
        local xcframework="$package/xcframeworks/$library.xcframework"
        [ -f "$xcframework/Info.plist" ] ||
            die "missing XCFramework metadata: $xcframework"
        for family in "${families[@]}"; do
            local binary
            binary="$(framework_binary "$xcframework" "$library" "$family")"
            [ -n "$binary" ] ||
                die "missing $library binary for $family"
            case "$family" in
                ios-device) expected_archs=arm64 ;;
                ios-simulator)
                    if [ "$minimal" = yes ]; then
                        expected_archs=arm64
                    else
                        expected_archs='arm64 x86_64'
                    fi
                    ;;
                maccatalyst) expected_archs='arm64 x86_64' ;;
            esac
            verify_framework_binary "$binary" "$library" "$expected_archs"
        done
    done

    for family in "${families[@]}"; do
        verify_transport_binary "$(framework_binary \
            "$package/xcframeworks/libavformat.xcframework" libavformat "$family")"
        verify_iconv_binary "$(framework_binary \
            "$package/xcframeworks/libavcodec.xcframework" libavcodec "$family")"
        verify_public_wrapper_link "$package" "$family"
    done
}

prepare() {
    assert_pinned_source
    prepare_gmp_source
    prepare_nettle_source
    prepare_gnutls_source
    prepare_nasm_source
    record_transport_patch_metadata
    record_global_metadata
}

build_requested_targets() {
    local targets=("$@")
    local target
    for target in "${targets[@]}"; do
        build_target "$target"
    done
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            prepare|build|package-minimal|package|verify|all)
                action="$1"
                ;;
            --work-root)
                [ "$#" -ge 2 ] || die "--work-root requires a value"
                work_root="$2"
                shift
                ;;
            --jobs)
                [ "$#" -ge 2 ] || die "--jobs requires a value"
                jobs="$2"
                shift
                ;;
            --minimal)
                minimal_verification=yes
                ;;
            --without-transport-patches)
                patch_mode=none
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                if contains_target "$1"; then
                    requested_targets+=("$1")
                else
                    die "unknown action, target, or option: $1"
                fi
                ;;
        esac
        shift
    done
}

parse_arguments "$@"
assert_safe_work_root
assert_jobs
case "$patch_mode" in
    auto|none) ;;
    *) die "IRPLAYER_FFMPEG_PATCH_MODE must be auto or none" ;;
esac

for command in git curl shasum tar make xcodebuild xcrun lipo otool \
    install_name_tool codesign ditto; do
    require_command "$command"
done

case "$action" in
    prepare)
        prepare
        ;;
    build)
        prepare
        if [ "${#requested_targets[@]}" -eq 0 ]; then
            build_requested_targets "${all_targets[@]}"
        else
            build_requested_targets "${requested_targets[@]}"
        fi
        ;;
    package-minimal)
        prepare
        assert_stage_exists ios-device-arm64 ios-simulator-arm64
        package_frameworks "$(minimal_package_dir)" ios-device ios-simulator
        verify_package "$(minimal_package_dir)" yes
        make_package_metadata "$(minimal_package_dir)"
        write_package_artifact_checksums "$(minimal_package_dir)"
        ;;
    package)
        prepare
        assert_stage_exists "${all_targets[@]}"
        package_frameworks "$(full_package_dir)" ios-device ios-simulator maccatalyst
        verify_package "$(full_package_dir)" no
        make_package_metadata "$(full_package_dir)"
        write_package_artifact_checksums "$(full_package_dir)"
        ;;
    verify)
        prepare
        if [ "$minimal_verification" = yes ]; then
            verify_package "$(minimal_package_dir)" yes
            verify_package_artifact_checksums "$(minimal_package_dir)"
        else
            verify_package "$(full_package_dir)" no
            verify_package_artifact_checksums "$(full_package_dir)"
        fi
        ;;
    all)
        prepare
        build_requested_targets "${all_targets[@]}"
        package_frameworks "$(full_package_dir)" ios-device ios-simulator maccatalyst
        verify_package "$(full_package_dir)" no
        make_package_metadata "$(full_package_dir)"
        write_package_artifact_checksums "$(full_package_dir)"
        ;;
esac
