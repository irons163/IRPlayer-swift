# AGENTS.md — Audio

## Contents

- `IRAudioManager.swift` — Facade for graph commands, hardware format fallback,
  and synchronized audio-session event routing.
- `IRAudioGraphSession.swift` — Serialized, generation-scoped graph lifecycle.
- `IRAudioGraphDriver.swift` — Injectable Core Audio construction and teardown.
- `IRAudioRenderContext.swift` — Real-time callback binding, scratch storage,
  validation, conversion, and teardown fence.

## Purpose

Owns Core Audio output independently from decoded-frame consumption. FFmpeg
frame consumption belongs to `FFPlayer/IRFFAudioRenderer.swift`.

## Agent Notes

- Keep graph mutation behind `IRAudioGraphSession`; never publish a partially
  built `AUGraph`.
- The callback refcon must remain the retained `IRAudioRenderContext`, not a
  player or manager facade.
- Deactivate and drain the render context before graph stop or disposal.
- Keep manager-owned callback mechanics allocation-free and use non-blocking
  admission before entering a delegate.
- Tests: `IRAudioGraphDriverTests.swift`, `IRAudioGraphSessionTests.swift`,
  `IRAudioManagerTests.swift`, and `IRAudioManagerRenderTests.swift`.
