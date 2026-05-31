# AGENTS.md — Audio

## Contents

- `IRAudioManager.swift` — Audio output management for decoded audio frames.

## Purpose

Manages audio playback for the FFmpeg pipeline. Handles audio buffer scheduling and output.

## Agent Notes

- Shared by both player backends when audio output is needed.
- Tests: `IRAudioManagerTests.swift`.
- Audio threading is sensitive — avoid blocking calls in the audio callback path.
