# AGENTS.md — Sources

This is the top-level source directory for the IRPlayer framework.

## Structure

- `IRPlayer-swift/` — The main framework target root.
  - `Class/` — All Swift framework code (player, rendering, controllers, pipeline).
  - `Objc/` — Objective-C bridge code (`IRPlayerObjc` target) for FFmpeg error utilities.
  - `ThirdParty/` — FFmpeg wrapper target (`IRFFMpeg`) and pre-built xcframework binaries.
  - `include/` and `private_include/` — Bridging and module headers.
  - `IRPlayer_swift.h` — Umbrella header.
  - `IRPlayer_swift.docc/` — DocC documentation catalog.

## SPM Targets Mapping

| SPM Target      | Path                                     | Purpose                        |
|-----------------|------------------------------------------|--------------------------------|
| `IRPlayerSwift` | `Sources/` (excludes Objc, ThirdParty)   | Main Swift framework           |
| `IRPlayerObjc`  | `Sources/IRPlayer-swift/Objc/`           | Obj-C bridge for FFmpeg errors |
| `IRFFMpeg`      | `Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/` | FFmpeg C wrapper          |

## Agent Notes

- The `IRPlayerSwift` target depends on `IRPlayerObjc` and `IRFFMpeg`.
- The compile flag `IR_USE_METAL` is set for all targets — do not remove it.
- Metal shaders are in `Class/Core/Display/Metal/IRMetalShaders.metal` and processed as a resource.
- Linked system frameworks: Metal, MetalKit, CoreVideo, QuartzCore, AVFoundation.
