# 2.0 Release Prep Implementation Plan

> Historical note: this preliminary release-prep plan predates the completed
> 2.0 API and runtime redesign. Its sample release body is retained as an
> execution record, but is superseded by `docs/releases/2.0.md` and
> `docs/releases/2.0-migration.md`; in particular, its statement that no public
> API rename was planned is no longer the 2.0 compatibility contract.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare a reviewed and verified `2.0` release candidate without publishing the final tag prematurely.

**Architecture:** Keep SwiftPM release identity tag-driven. Use `codex/prepare-2.0-release` as the candidate branch, include the post-`1.0.3` hardening/coverage branch, bump Xcode generated Info.plist metadata, and store release notes in the repo before publishing.

**Tech Stack:** Swift Package Manager, Xcode project build settings, XCTest on iOS Simulator, GitHub CLI.

---

## File Structure

- Modify: `IRPlayer-swift.xcodeproj/project.pbxproj`
  - Set every `CURRENT_PROJECT_VERSION` build setting to `2`.
  - Set every `MARKETING_VERSION` build setting to `2.0`.
- Create: `docs/superpowers/specs/2026-07-06-2-0-release-prep-design.md`
  - Defines the release scope, non-goals, candidate base, and release gates.
- Create: `docs/superpowers/plans/2026-07-06-2-0-release-prep.md`
  - Gives the executable release-prep and final-release checklist.
- Create: `docs/releases/2.0.md`
  - Stores the draft GitHub release notes for review.

## Task 1: Create The Release Prep Branch

- [ ] **Step 1: Start from the repository root**

Run:

```sh
cd /Users/phil/Documents/github/IRPlayer-swift
git status --short --branch
```

Expected: current branch is clean before switching.

- [ ] **Step 2: Create the prep branch from the post-1.0.3 candidate base**

Run:

```sh
git fetch origin --tags --prune
git switch -c codex/prepare-2.0-release origin/codex/expand-test-coverage
```

Expected: branch `codex/prepare-2.0-release` is checked out and tracks the candidate base.

## Task 2: Bump Xcode Release Metadata

- [ ] **Step 1: Update Xcode build settings**

In `IRPlayer-swift.xcodeproj/project.pbxproj`, replace:

```text
CURRENT_PROJECT_VERSION = 1;
MARKETING_VERSION = 1.0;
```

with:

```text
CURRENT_PROJECT_VERSION = 2;
MARKETING_VERSION = 2.0;
```

- [ ] **Step 2: Verify only the expected version settings remain**

Run:

```sh
rg -n "CURRENT_PROJECT_VERSION|MARKETING_VERSION" IRPlayer-swift.xcodeproj/project.pbxproj
```

Expected: every `CURRENT_PROJECT_VERSION` is `2`; every `MARKETING_VERSION` is `2.0`.

## Task 3: Add Release Notes

- [ ] **Step 1: Create `docs/releases/2.0.md`**

Use this release body:

```markdown
# IRPlayer-swift 2.0

## Highlights

- Moves the release candidate onto the hardened Metal/SPM baseline after `1.0.3`.
- Loads Metal shader resources from the framework/module bundle path used by Swift Package Manager clients.
- Adds defensive guards around FFmpeg decoder/audio/video flows, AVPlayer error handling, PhotoSaver diagnostics, sensor motion deltas, and render fallback paths.
- Expands regression coverage across AVPlayer, FFmpeg decoder/player, audio manager, GL/Metal rendering, gesture controllers, transforms, PhotoSaver, and model payload utilities.

## Compatibility

- Swift Package Manager remains the supported installation path.
- The package still declares iOS 15+ support in `Package.swift`.
- No intentional public API rename is included in the release prep branch.

## Verification

- `git diff --check`
- Full iOS Simulator tests with scheme `IRPlayer-swift`
```

## Task 4: Verify The Candidate

- [ ] **Step 1: Check formatting whitespace**

Run:

```sh
git diff --check
```

Expected: command exits `0`.

- [ ] **Step 2: Run the full iOS Simulator suite**

Use XcodeBuildMCP session defaults:

```text
projectPath: /Users/phil/Documents/github/IRPlayer-swift/IRPlayer-swift.xcodeproj
scheme: IRPlayer-swift
simulator: iPhone 17
```

Expected: the test summary reports zero failures.

- [ ] **Step 3: Confirm no `2.0` release already exists**

Run:

```sh
git tag -l '2.0'
gh release view 2.0 --repo irons163/IRPlayer-swift --json tagName,name,isDraft,isPrerelease,publishedAt,url,targetCommitish
```

Expected: no local tag output; GitHub CLI prints `release not found`.

## Task 5: Commit And Push The Prep Branch

- [ ] **Step 1: Review the final diff**

Run:

```sh
git diff --stat
git diff -- IRPlayer-swift.xcodeproj/project.pbxproj docs/superpowers/specs/2026-07-06-2-0-release-prep-design.md docs/superpowers/plans/2026-07-06-2-0-release-prep.md docs/releases/2.0.md
```

Expected: the diff contains only release prep metadata and documentation.

- [ ] **Step 2: Commit**

Run:

```sh
git add IRPlayer-swift.xcodeproj/project.pbxproj docs/superpowers/specs/2026-07-06-2-0-release-prep-design.md docs/superpowers/plans/2026-07-06-2-0-release-prep.md docs/releases/2.0.md
git commit -m "chore: prepare 2.0 release candidate"
```

Expected: one release prep commit is created.

- [ ] **Step 3: Push**

Run:

```sh
git push -u origin codex/prepare-2.0-release
```

Expected: remote branch `origin/codex/prepare-2.0-release` exists.

## Task 6: Final Release After Review Approval

- [ ] **Step 1: Merge the prep branch to main**

Run:

```sh
git switch main
git pull --ff-only origin main
git merge --no-ff codex/prepare-2.0-release
```

Expected: merge succeeds without conflicts.

- [ ] **Step 2: Verify the merged result**

Run the same verification gates from Task 4 on `main`.

Expected: `git diff --check` exits `0`; full iOS Simulator tests report zero failures.

- [ ] **Step 3: Tag and publish**

Run:

```sh
git tag 2.0
git push origin main
git push origin 2.0
gh release create 2.0 --repo irons163/IRPlayer-swift --verify-tag --latest --title "2.0" --notes-file docs/releases/2.0.md
```

Expected: GitHub Release `2.0` is published against tag `2.0`.
