# AGENTS.md

This document gives coding agents practical guidance for working in this repository.

## Project Snapshot

- Name: `IRPlayer-swift`
- Language mix: Swift + Objective-C/C + Metal shaders
- Package manager: Swift Package Manager
- Platforms: iOS 15+
- Core domain: Video playback and rendering (2D, VR, fisheye, distortion, multi-view)

## Repository Layout

- `Sources/IRPlayer-swift/Class/`
  - Main Swift framework code (player, rendering, controls, pipeline)
- `Sources/IRPlayer-swift/Objc/`
  - Objective-C bridge and legacy/core interop
- `Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/`
  - FFmpeg wrapper target and headers
- `Sources/IRPlayer-swift/Class/Core/Display/Metal/`
  - Metal renderer code and shader resources
- `Tests/IRPlayer-swiftTests/`
  - Unit tests for render pipeline, decoder flow, transforms, and utilities
- `SPMDemo/`
  - Demo app workspace and sample media for manual verification

## Docs Folder Usage

- Start here for implementation guidance: `docs/superpowers/`.
- `docs/superpowers/specs/*.md` describes the design intent, goals, non-goals, and acceptance criteria.
- `docs/superpowers/plans/*.md` provides executable step-by-step tasks, expected file edits, and validation commands.
- Current lifecycle policy docs:
  - `docs/superpowers/specs/2026-05-26-player-lifecycle-policy-design.md`
  - `docs/superpowers/plans/2026-05-26-player-lifecycle-policy.md`
- Recommended agent flow:
  1. Read the matching `specs` doc first to understand boundaries.
  2. Execute tasks from `plans` in order with small diffs.
  3. Run the listed focused tests before broad/full-suite runs.
  4. Report what was completed and what remains.

## Build And Test

Run from repository root unless noted.

```bash
swift --version
swift package resolve
swift build
swift test
```

For Xcode workflows (example):

```bash
xcodebuild -project IRPlayer-swift.xcodeproj -list
xcodebuild -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'generic/platform=iOS' build
```

If the scheme name differs locally, use the output of `-list`.

## Agent Working Rules

- Make the smallest safe change needed for the request.
- Do not reformat unrelated code or move files without request.
- Preserve public APIs unless asked to change them.
- Prefer existing abstractions over introducing new architecture.
- Keep Objective-C/C interop stable when editing Swift-facing boundaries.
- When touching rendering paths, consider mode-specific behavior:
  - 2D
  - VR
  - fisheye
  - fish2pano
  - distortion
  - multi4P

## Rendering-Specific Notes

- The rendering stack is sensitive to threading and frame timing.
- Avoid blocking the main thread in hot render paths.
- Keep viewport/transform updates consistent with existing controller flows.
- For Metal updates, verify drawable size assumptions and texture layout calculations.
- Prefer guard-based early exits in per-frame code to limit invalid state propagation.

## Testing Expectations

When changing code:

- Run relevant tests first, then broader tests if impact is cross-cutting.
- Add or update tests in `Tests/IRPlayer-swiftTests/` for behavioral changes.
- For render-path changes, include at least one regression test for the affected mode or helper.
- If full validation is not possible locally, state exactly what was run and what remains.

## Change Hygiene

- Keep commits focused and explain why the change is needed.
- Document non-obvious behavior changes in code comments or PR notes.
- Do not remove existing assets, binaries, or third-party folders unless explicitly requested.
- Flag risky assumptions early (for example: pixel format, texture size, or controller defaults).

## Definition Of Done (For Agents)

- Requested behavior implemented.
- Affected tests pass (or clear rationale provided if they cannot be run).
- No unrelated file churn.
- Build/test commands and outcomes are reported succinctly.
