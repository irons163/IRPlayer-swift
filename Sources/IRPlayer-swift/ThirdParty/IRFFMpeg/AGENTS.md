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
- Source: pinned FFmpeg n6.1.6 with the repository's GnuTLS 3.8.13,
  Nettle/Hogweed 3.10.2, and GMP 6.3.0 recipe.
- Preserve `Provenance/ffmpeg-n6.1.6-gnutls-sectrust` with the matching
  binaries. It contains source/patch identities, per-slice configuration,
  recipe-role attestations, artifact inventories, and license notices.
