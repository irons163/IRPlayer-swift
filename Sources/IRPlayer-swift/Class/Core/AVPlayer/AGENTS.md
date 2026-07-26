# AGENTS.md — AVPlayer

## Contents

- `IRAVPlayer.swift` — Playback commands, facade state, state-transition
  semantics, and time normalization.
- `IRAVPlayerLifecycle.swift` — Session activation, replacement, reset, and
  item-status/error event translation.
- `IRAVPlayerPresentation.swift` — Time, snapshot, pixel-buffer, and
  generation-fenced tick consumption.
- `IRAVPlayerPresentationLoop.swift` — VR display-link activation, AVPlayer
  session-token binding, stale-tick rejection, and terminal teardown.
- `IRAVPlayerTracks.swift` — Track discovery, selection, metadata parsing,
  and fallback semantics.
- `IRAVPlayerSession.swift` — Generation-scoped AVFoundation resources,
  observations, leases, and teardown.

## Purpose

Provides the native system player backend. Used when `IRPlayerDecoder` is configured for AVPlayer mode (the default for standard video URLs).

## Agent Notes

- This is the simpler of the two player backends (vs FFPlayer).
- Handles standard HTTP/file-based video URLs via AVFoundation.
- Does not support custom video frames or advanced decode pipelines — use FFPlayer for those.
- Treat custom request headers as an FFmpeg capability. Do not emulate them
  with `AVAssetResourceLoader`; that public boundary cannot guarantee headers
  on every HLS playlist and segment request.
- Keep all AV asset/item/player/output and observation ownership inside
  `IRAVPlayerSession`.
- Gate asynchronous work with the session token and exact resource identity.
- Normal playback uses a real display-owned `AVPlayerLayer`; VR alone uses
  `AVPlayerItemVideoOutput` and display-link polling.
- Keep timer/proxy ownership in the shared `IRDisplayLinkDriving` boundary and
  VR presentation generations in `IRAVPlayerPresentationLoop`. Deactivate
  before session reset or display detachment.
- Do not invoke backend-host callbacks while a session lock or lease is held.
- Keep AVPlayer-only semantics with their owning facade/lifecycle/tracks
  extension. Do not introduce forwarding-only policy mirrors.
- Tests: `IRAVPlayerSemanticsTests.swift`, `IRAVPlayerTests.swift`,
  `IRAVPlayerPresentationLoopTests.swift`, and
  `IRAVPlayerSessionTests.swift`.
