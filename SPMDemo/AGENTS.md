# AGENTS.md — SPMDemo

Demo application for manual verification of the IRPlayer framework.

## Structure

| Directory             | Purpose                                          |
|-----------------------|--------------------------------------------------|
| `SPMDemo/`            | Demo app source code and media files             |
| `SPMDemo.xcodeproj/`  | Xcode project for the demo app                   |
| `SPMDemoTests/`       | Basic unit tests for the demo app                |
| `SPMDemoUITests/`     | UI tests for the demo app                        |
| `ScreenShots/`        | Screenshot assets for README documentation       |

## Demo App Files (`SPMDemo/`)

| File                          | Purpose                                     |
|-------------------------------|---------------------------------------------|
| `AppDelegate.swift`           | App lifecycle delegate                      |
| `SceneDelegate.swift`         | Scene lifecycle delegate                    |
| `ViewController.swift`        | Main menu — lists all demo modes            |
| `PlayerViewController.swift`  | Player screen — configures and runs player  |
| `PlayerViewController.xib`    | Player UI layout                            |
| `Info.plist`                  | App configuration                           |

## Bundled Media Files

| File                   | Used For                        |
|------------------------|---------------------------------|
| `i-see-fire.mp4`      | Normal 2D playback demos        |
| `google-help-vr.mp4`  | VR and VR Box mode demos        |
| `fisheye-demo.mp4`    | Fisheye, panorama, multi-view demos |

## Demo Modes

The demo app showcases all supported rendering modes:
1. AVPlayer Normal
2. AVPlayer VR
3. AVPlayer VR Box
4. FFmpeg Normal (software decode)
5. FFmpeg Normal (hardware decode)
6. FFmpeg Fisheye (hardware decode)
7. FFmpeg Panorama (hardware decode)
8. FFmpeg Multi-modes with mode selection

## Agent Notes

- The demo app consumes `IRPlayer` as a local SPM dependency.
- Use this app for manual verification of rendering and playback changes.
- Do not modify bundled media files.
- Screenshots in `ScreenShots/` are referenced by the root `README.md`.
