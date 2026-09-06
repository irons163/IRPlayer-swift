# Rendering modes

``IRVideoType`` selects the default rendering setup for a source. The player's
display view is a UIKit surface that can host an AVPlayerLayer or Metal
renderers depending on the backend and presentation mode.

| Video type | Default rendering | Interaction |
| --- | --- | --- |
| `.normal` | Flat 2D | Gestures |
| `.vr` | Stereoscopic VR | Gestures |
| `.vr` with ``IRDisplayMode/box`` | VR Box distortion | Device motion |
| `.fisheye` | 3D fisheye | Gestures |
| `.pano` | Fisheye-to-panorama | Gestures |
| `.custom` | Caller-provided render mode list | Gestures |

Set ``IRPlayerImp/viewGravityMode`` to ``IRGravityMode/resize``,
``IRGravityMode/resizeAspect``, or ``IRGravityMode/resizeAspectFill``. Call
``IRPlayerImp/updateGraphicsViewFrame(frame:)`` after the containing view's
layout changes. ``IRPlayerImp/snapshot()`` returns a `UIImage?` from the display
surface. It may be `nil` only when that surface is unavailable; before the
first render the current implementation can return an empty placeholder image,
so a non-`nil` value is not proof that a frame has been displayed.

For a custom player UI, call ``IRPlayerImp/setupPlayerView(_:)`` with a `UIView`
on the main thread. The supplied view is pinned to the display view's
bounds; an existing attached player subview is removed first.

## Supply custom modes

The public concrete modes are ``IRGLRenderMode2D``,
``IRGLRenderMode2DFisheye2Pano``, ``IRGLRenderMode3DFisheye``, and
``IRGLRenderModeMulti4P``. Assign the same instances to
``IRPlayerImp/renderModes`` and use one of those instances with
``IRPlayerImp/selectRenderMode(renderMode:)``:

```swift
let normal = IRGLRenderMode2D()
normal.name = "Raw"
normal.shiftController.enabled = false

let panorama = IRGLRenderMode2DFisheye2Pano()
panorama.name = "Panorama"
panorama.contentMode = .scaleAspectFill
panorama.wideDegreeX = 360
panorama.wideDegreeY = 20

let fisheye = IRGLRenderMode3DFisheye()
fisheye.name = "Fisheye"
fisheye.parameter = IRFisheyeParameter(
    width: 0,
    height: 0,
    up: false,
    rx: 0,
    ry: 0,
    cx: 0,
    cy: 0,
    latmax: 80
)

let modes: [IRGLRenderMode] = [normal, panorama, fisheye]
player.renderModes = modes
player.load(IRMediaSource(
    url: mediaURL,
    videoType: .custom,
    backendPreference: .ffmpeg
))
player.selectRenderMode(renderMode: panorama)
```

``IRPlayerImp/selectRenderMode(renderMode:)`` only accepts an object currently
registered in `renderModes`; constructing a second mode with the same settings
does not select the registered one. ``IRGLRenderMode/contentMode`` accepts
``IRGLRenderContentMode/scaleAspectFit``,
``IRGLRenderContentMode/scaleAspectFill``, and
``IRGLRenderContentMode/scaleToFill``. ``IRFisheyeParameter`` is configured at
construction time; zero width and height allow the fisheye program to update
dimensions from the first frame when automatic update is active.

The internal VR and distortion mode classes are selected by the player's
``IRVideoType`` and ``IRDisplayMode`` configuration. They are not public
constructors for application code.
