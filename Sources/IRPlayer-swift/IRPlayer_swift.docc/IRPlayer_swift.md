# ``IRPlayer_swift``

Build AVFoundation and FFmpeg playback experiences with typed sources,
configuration, events, and Metal-backed immersive rendering.

## Overview

Create an ``IRPlayer`` with ``IRPlayerConfiguration``, attach its view, observe
``IRPlayerEvent`` values, and load an ``IRMediaSource``. The player selects and
coordinates AVFoundation or FFmpeg without exposing backend objects to callers.

## Topics

### Playback

- ``IRPlayer``
- ``IRPlayerConfiguration``
- ``IRMediaSource``
- ``IRPlaybackBackendPreference``
- ``IRPlayerEvent``
- ``IRPlayerObservation``
- ``IRPlayerTimeSnapshot``
