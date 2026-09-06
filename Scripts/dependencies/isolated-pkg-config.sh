#!/usr/bin/env bash
#
# Minimal, fail-closed pkg-config facade for the three static libraries that
# form the isolated iOS GnuTLS dependency graph. It intentionally does not
# inspect host pkg-config paths, so a cross build cannot accidentally link a
# macOS Homebrew dependency.

set -euo pipefail
IFS=$'\n\t'

die() {
    printf 'isolated-pkg-config: %s\n' "$*" >&2
    exit 1
}

require_prefix() {
    local prefix="$1"
    [ -n "$prefix" ] || die "required target prefix is unset"
    [ -d "$prefix/include" ] || die "missing include directory: $prefix/include"
    [ -d "$prefix/lib" ] || die "missing library directory: $prefix/lib"
}

numeric_version_compare() {
    local lhs="$1" rhs="$2" index lhs_part rhs_part
    local IFS=.
    local lhs_parts=($lhs) rhs_parts=($rhs)
    local length="${#lhs_parts[@]}"
    [ "${#rhs_parts[@]}" -le "$length" ] || length="${#rhs_parts[@]}"
    for ((index=0; index<length; index++)); do
        lhs_part="${lhs_parts[index]:-0}"
        rhs_part="${rhs_parts[index]:-0}"
        [[ "$lhs_part" =~ ^[0-9]+$ && "$rhs_part" =~ ^[0-9]+$ ]] ||
            die "non-numeric version component"
        ((10#$lhs_part > 10#$rhs_part)) && { printf '1\n'; return; }
        ((10#$lhs_part < 10#$rhs_part)) && { printf '%s\n' '-1'; return; }
    done
    printf '0\n'
}

if [ "$#" -eq 1 ] && [ "$1" = --version ]; then
    printf '0.29.2-irplayer-isolated\n'
    exit 0
fi
if [ "$#" -eq 2 ] && [ "$1" = --atleast-pkgconfig-version ]; then
    # The facade implements the subset required by this recipe and identifies
    # as pkg-config 0.29.2 for configure's capability check.
    [ "$(numeric_version_compare 0.29.2 "$2")" != -1 ] || exit 1
    exit 0
fi

requested_package=""
requested_operator=""
requested_version=""
package_count=0

record_package_query() {
    local package="$1"
    local operator="${2:-}"
    local version="${3:-}"
    package_count=$((package_count + 1))
    [ "$package_count" -eq 1 ] || die "multiple-package queries are unsupported: $*"
    requested_package="$package"
    requested_operator="$operator"
    requested_version="$version"
}

pending_operator=""
for argument in "$@"; do
    case "$argument" in
        --*) ;;
        '>='|'<='|'='|'>'|'<') pending_operator="$argument" ;;
        nettle|hogweed|gmp|gnutls)
            record_package_query "$argument"
            ;;
        nettle\ *|hogweed\ *|gmp\ *|gnutls\ *)
            # pkg-config commonly passes a whole dependency expression as one
            # argv item (for example "gnutls >= 3.8.0").
            IFS=' ' read -r package operator version extra <<< "$argument"
            [ -z "${extra:-}" ] && [ -n "${version:-}" ] ||
                die "malformed package expression: $argument"
            case "$operator" in '>='|'<='|'='|'>'|'<') ;; *) die "unsupported version operator: $operator" ;; esac
            record_package_query "$package" "$operator" "$version"
            ;;
        [0-9]*)
            [ -n "$pending_operator" ] && [ -n "$requested_package" ] ||
                die "version without a package/operator: $argument"
            requested_operator="$pending_operator"
            requested_version="$argument"
            pending_operator=""
            ;;
        *) die "unsupported package query: $argument" ;;
    esac
done
[ -z "$pending_operator" ] || die "version operator without a version"

if [ -z "$requested_package" ]; then
    for argument in "$@"; do
        case "$argument" in
            --version)
                printf '0.29.2-irplayer-isolated\n'
                exit 0
                ;;
            --atleast-pkgconfig-version)
                # GnuTLS only requires pkg-config >= 0.9.0. This facade has
                # the small, deterministic interface used by this recipe.
                exit 0
                ;;
        esac
    done
    # Optional GnuTLS integrations (for example p11-kit) must remain absent
    # rather than accidentally resolving through a host installation.
    for argument in "$@"; do
        case "$argument" in
            --exists|--atleast-version|--atleast-version=*) exit 1 ;;
        esac
    done
    die "unsupported package query: $*"
fi

case "$requested_package" in
    nettle|hogweed)
        target_prefix="${IRPLAYER_PKG_CONFIG_NETTLE_PREFIX:-}"
        target_version=3.10.2
        require_prefix "$target_prefix"
        cflags="-I$target_prefix/include"
        ;;
    gmp)
        target_prefix="${IRPLAYER_PKG_CONFIG_GMP_PREFIX:-}"
        target_version=6.3.0
        require_prefix "$target_prefix"
        cflags="-I$target_prefix/include"
        ;;
    gnutls)
        target_prefix="${IRPLAYER_PKG_CONFIG_GNUTLS_PREFIX:-}"
        require_prefix "$target_prefix"
        target_version=3.8.13
        cflags="-I$target_prefix/include"
        ;;
esac

if [ -n "$requested_operator" ]; then
    comparison="$(numeric_version_compare "$target_version" "$requested_version")"
    case "$requested_operator:$comparison" in
        '=:'0|'>=:'0|'>=:'1|'<=:'0|'<=:'-1|'>:'1|'<:'-1) ;;
        *) exit 1 ;;
    esac
fi

for argument in "$@"; do
    case "$argument" in
        --exists|--print-errors|--short-errors|--silence-errors|--static)
            ;;
        --atleast-pkgconfig-version|--atleast-version|--max-version|--exact-version)
            die "unsupported version query form: $*"
            ;;
        --cflags|--cflags-only-I|--libs|--modversion|--variable=includedir)
            ;;
        nettle|nettle\ *|hogweed|hogweed\ *|gmp|gmp\ *|gnutls|gnutls\ *|'>='|'<='|'='|'>'|'<'|[0-9]*)
            ;;
        *) die "unsupported pkg-config argument: $argument" ;;
    esac
done

want_cflags=no
want_cflags_only_i=no
want_libs=no
want_modversion=no
want_includedir=no
for argument in "$@"; do
    case "$argument" in
        --cflags) want_cflags=yes ;;
        --cflags-only-I) want_cflags_only_i=yes ;;
        --libs) want_libs=yes ;;
        --modversion) want_modversion=yes ;;
        --variable=includedir) want_includedir=yes ;;
    esac
done

[ "$want_modversion" = no ] || {
    printf '%s\n' "$target_version"
    exit 0
}

[ "$want_includedir" = no ] || {
    printf '%s/include\n' "$target_prefix"
    exit 0
}

# Resolve the complete static dependency closure before emitting any output.
# This keeps combined --cflags/--libs failures atomic: callers never receive a
# usable partial include path when a transitive target prefix is absent.
if [ "$want_libs" = yes ]; then
    case "$requested_package" in
        nettle|hogweed) require_prefix "${IRPLAYER_PKG_CONFIG_GMP_PREFIX:-}" ;;
        gnutls)
            require_prefix "${IRPLAYER_PKG_CONFIG_NETTLE_PREFIX:-}"
            require_prefix "${IRPLAYER_PKG_CONFIG_GMP_PREFIX:-}"
            ;;
    esac
fi

if [ "$want_cflags" = yes ] || [ "$want_cflags_only_i" = yes ]; then
    printf '%s' "$cflags"
fi

if [ "$want_libs" = yes ]; then
    if [ "$want_cflags" = yes ] || [ "$want_cflags_only_i" = yes ]; then
        printf ' '
    fi
    case "$requested_package" in
        nettle)
            printf '%s' "-L$target_prefix/lib -lnettle -L${IRPLAYER_PKG_CONFIG_GMP_PREFIX:-}/lib -lgmp"
            ;;
        hogweed)
            printf '%s' "-L$target_prefix/lib -lhogweed -lnettle -L${IRPLAYER_PKG_CONFIG_GMP_PREFIX:-}/lib -lgmp"
            ;;
        gmp)
            printf '%s' "-L$target_prefix/lib -lgmp"
            ;;
        gnutls)
            printf '%s' "-L$target_prefix/lib -lgnutls -L${IRPLAYER_PKG_CONFIG_NETTLE_PREFIX:-}/lib -lhogweed -lnettle -L${IRPLAYER_PKG_CONFIG_GMP_PREFIX:-}/lib -lgmp -liconv"
            ;;
    esac
fi

if [ "$want_cflags" = yes ] || [ "$want_cflags_only_i" = yes ] || [ "$want_libs" = yes ]; then
    printf '\n'
fi
