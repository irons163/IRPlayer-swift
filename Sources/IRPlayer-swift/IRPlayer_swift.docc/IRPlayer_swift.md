# ``IRPlayer_swift``

Build AVFoundation and FFmpeg playback experiences with typed sources,
configuration, events, and Metal-backed immersive rendering.

## Overview

Create an ``IRPlayer`` with ``IRPlayerConfiguration``, attach its view, observe
``IRPlayerEvent`` values, and load an ``IRMediaSource``. The player selects and
coordinates AVFoundation or FFmpeg without exposing backend objects to callers.

This catalog documents the current development line of the package. The
published `2.0` tag predates the Swift-first API redesign; pin the exact
release or candidate ref that your application has reviewed.

## Topics

### Start here

- <GettingStarted>
- <PlaybackLifecycle>
- <RenderingModes>
- <CustomVideoInput>
- <ErrorsAndCompatibility>

### Playback API

- ``IRPlayer``
- ``IRPlayerConfiguration``
- ``IRMediaSource``
- ``IRPlaybackBackendPreference``
- ``IRPlayerEvent``
- ``IRPlayerObservation``
- ``IRPlayerTimeSnapshot``

### Rendering and input API

- ``IRVideoType``
- ``IRDisplayMode``
- ``IRGravityMode``
- ``IRGLRenderMode``
- ``IRGLRenderMode2D``
- ``IRGLRenderMode2DFisheye2Pano``
- ``IRGLRenderMode3DFisheye``
- ``IRGLRenderModeMulti4P``
- ``IRFFVideoInput``
- ``IRVideoFrameRGB``
- ``IRFFCVYUVVideoFrame``
