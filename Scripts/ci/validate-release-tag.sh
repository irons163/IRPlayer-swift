#!/usr/bin/env bash

set -euo pipefail

tag="${1:-}"
release_branch="${2:-origin/main}"
expected_commit="${3:-${GITHUB_SHA:-HEAD}}"

if [[ -z "$tag" ]]; then
    echo "Usage: $0 <tag> [release-branch] [expected-commit]" >&2
    exit 2
fi

if [[ ! "$tag" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
    echo "Invalid release tag '$tag'. Use 2.0, 2.0.1, v2.0.1, or a prerelease such as 2.1.0-rc.1." >&2
    exit 1
fi

tag_ref="refs/tags/$tag"
if ! git show-ref --verify --quiet "$tag_ref"; then
    echo "Release tag does not exist in this checkout: $tag" >&2
    exit 1
fi

if ! git rev-parse --verify --quiet "$release_branch^{commit}" >/dev/null; then
    echo "Release branch is not available in this checkout: $release_branch" >&2
    exit 1
fi

tag_commit="$(git rev-parse "$tag_ref^{commit}")"
expected_commit_sha="$(git rev-parse "$expected_commit^{commit}")"

if [[ "$tag_commit" != "$expected_commit_sha" ]]; then
    echo "Tag $tag resolves to $tag_commit, but the workflow is validating $expected_commit_sha." >&2
    exit 1
fi

if ! git merge-base --is-ancestor "$tag_commit" "$release_branch"; then
    echo "Tag $tag is not reachable from $release_branch; merge the release commit before tagging." >&2
    exit 1
fi

printf 'Validated release tag %s at %s on %s.\n' "$tag" "$tag_commit" "$release_branch"
