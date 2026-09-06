#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$script_dir/validate-release-tag.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/irplayer-tag-tests.XXXXXX")"
cd "$fixture"
git init -q
git config user.name "Release validator test"
git config user.email "release-test@example.invalid"
git commit -qm initial --allow-empty
git branch -M main
initial_commit="$(git rev-parse HEAD)"
git tag 2.0
git tag -a v2.0.1 -m annotated
git tag 2.1.0-rc.1

expect_success() {
    if ! bash "$validator" "$@" >"$fixture/result.log" 2>&1; then
        cat "$fixture/result.log" >&2
        exit 1
    fi
}

expect_failure() {
    if bash "$validator" "$@" >"$fixture/result.log" 2>&1; then
        printf 'Unexpected success: %s\n' "$*" >&2
        exit 1
    fi
}

expect_success 2.0 main "$initial_commit"
expect_success v2.0.1 main "$initial_commit"
expect_success 2.1.0-rc.1 main "$initial_commit"
expect_failure '' main "$initial_commit"
expect_failure '2.0;false' main "$initial_commit"
expect_failure 2.0.0.0 main "$initial_commit"
expect_failure 9.0 main "$initial_commit"
expect_failure 2.0 missing-branch "$initial_commit"

git checkout -qb unmerged
git commit -qm unmerged --allow-empty
git tag 3.0
expect_failure 3.0 main HEAD
expect_failure 2.0 main HEAD
git checkout -q main
git merge -q --ff-only unmerged
expect_success 3.0 main HEAD
expect_success 2.0 main "$initial_commit"

printf 'Release tag regression tests passed. Fixture: %s\n' "$fixture"
