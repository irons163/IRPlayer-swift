# AGENTS.md — AVPlayer

## Contents

- `IRAVPlayer.swift` — Wrapper around Apple's `AVPlayer` for standard video playback.

## Purpose

Provides the native system player backend. Used when `IRPlayerDecoder` is configured for AVPlayer mode (the default for standard video URLs).

## Agent Notes

- This is the simpler of the two player backends (vs FFPlayer).
- Handles standard HTTP/file-based video URLs via AVFoundation.
- Does not support custom video frames or advanced decode pipelines — use FFPlayer for those.
- Tests: `IRAVPlayerTests.swift`.
