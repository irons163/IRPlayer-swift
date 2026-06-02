# AGENTS.md — IRFFMpeg

FFmpeg C wrapper target (`IRFFMpeg` SPM target).

## Structure

| Path          | Purpose                                                   |
|---------------|-----------------------------------------------------------|
| `IRFFMpeg.m`  | Objective-C implementation file for FFmpeg wrapper         |
| `include/`    | Public headers (`IRFFMpeg.h`, `module.modulemap`)         |
| `Libs/`       | Pre-built FFmpeg xcframeworks (binary targets)             |

## Binary Targets in `Libs/`

| Framework              | Purpose                         |
|------------------------|---------------------------------|
| `libavcodec.xcframework`    | Audio/video codec library  |
| `libavformat.xcframework`   | Container format I/O       |
| `libavutil.xcframework`     | Utility functions          |
| `libswresample.xcframework` | Audio resampling           |
| `libswscale.xcframework`    | Video scaling/conversion   |
| `libavdevice.xcframework`   | Device I/O (not linked)    |
| `libavfilter.xcframework`   | Filter graphs (not linked) |

## Agent Notes

- The `IRFFMpeg` target depends on: `libavcodec`, `libavformat`, `libavutil`, `libswresample`, `libswscale`.
- `libavdevice` and `libavfilter` are present but not linked by default.
- These are pre-built binaries — do not attempt to rebuild them in CI.
- The `IR_USE_METAL` compile flag is set for this target.
- Source: [ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit).
