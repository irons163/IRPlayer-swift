# AGENTS.md — Objc

Objective-C bridge code for the `IRPlayerObjc` SPM target.

## Files

| File                            | Purpose                                     |
|---------------------------------|---------------------------------------------|
| `IRFFMpegErrorUtil.m`           | FFmpeg error code to NSError conversion     |
| `include/IRFFMpegErrorUtil.h`   | Public header for the error utility         |
| `include/module.modulemap`      | Clang module map for Swift interop          |

## Agent Notes

- This is a minimal Objective-C target that bridges FFmpeg C error codes to Foundation types.
- Depends on `libavutil` binary target for FFmpeg error definitions.
- The module map in `include/` enables this target to be imported from Swift.
- Keep the interface surface minimal — only add bridge code here that cannot be done in pure Swift.
- The `IR_USE_METAL` compile flag is set for this target.
