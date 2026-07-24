# FFmpeg Semantics Consolidation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-ffmpeg-semantics-consolidation-design.md`.

## Phase 1: Audit and Baseline

- [x] Inventory all remaining FFmpeg policies, owners, loop consumers, tests,
  and project entries.
- [x] Record the focused audio/video/decoder/tool/loop baseline.

## Phase 2: Owner Semantics

- [x] Add shared `IRFFDecodeResult` value semantics.
- [x] Move audio arithmetic and decode admission to `IRFFAudioDecoder`.
- [x] Move video timing and decode admission to `IRFFVideoDecoder`.
- [x] Move audio, buffering, packet, and display transitions to `IRFFDecoder`.
- [x] Route read/display loop states through decoder-owned semantics.
- [x] Move error translation and stream timing to `IRFFTools`.
- [x] Remove all seven policy files and Xcode project entries.
- [x] Update local architecture guidance.

## Phase 3: Test Architecture

- [x] Remove audio/video/decoder/tool wrapper-mirror tests.
- [x] Rename policy suites to decoder owner-semantic suites.
- [x] Add exact narrowing, malformed clock, and derived-overflow tables.
- [x] Preserve real audio/video decode, queue, and loop integration coverage.

## Phase 4: Verification

- [x] Run focused audio, video, decoder, tool, and loop suites.
- [x] Run affected decoder/runtime boundaries under Thread Sanitizer.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project, stale-symbol, warning, policy-count, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Audio decoder, video decoder, decoder audio/display/packet policy, decoder
  operation, read-loop, display-loop, and FFmpeg tool suites: 115 passed, 0
  failed, 0 skipped.
- The exact suite counts were extracted from the already completed current-tree
  full result bundle after Xcode twice stalled before materializing a new test
  worker:
  `/private/tmp/irplayer-playback-value-full.xcresult`.

## Verification Results

- Focused audio, video, coordinating decoder semantics, operation, read/display
  loop, and tool suites: 124 passed, 0 failed, 0 skipped.
  Result: `/private/tmp/irplayer-ffmpeg-focused-final.xcresult`.
- The same 124 focused tests under Thread Sanitizer: 124 passed, 0 failed, 0
  skipped, with no sanitizer findings.
  Result: `/private/tmp/irplayer-ffmpeg-tsan-final.xcresult`.
- Full iOS Simulator suite: 1336 passed, 0 failed, 0 skipped.
  Result: `/private/tmp/irplayer-ffmpeg-full-final.xcresult`.
- Generic iOS device Release build: passed with 0 errors and 0 warnings.
  Result: `/private/tmp/irplayer-ffmpeg-release-final.xcresult`.
- The shared real-video fixture completion timeout was increased from 5 to 30
  seconds after loaded `AVAssetWriter` completion caused environmental skips;
  the formerly skipped targeted cases then passed, and the final focused,
  sanitizer, and full runs completed with zero skips.
- Xcode project parsing, deleted-symbol scans, policy count, changed-source
  warning scan, Swift syntax, and whitespace checks pass. The policy inventory
  is 10 files, all in RenderKit.
