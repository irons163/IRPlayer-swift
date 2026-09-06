# AGENTS.md — ThirdParty

Third-party dependencies, currently FFmpeg only.

## Structure

- `IRFFMpeg/` — FFmpeg wrapper target and pre-built binaries.

## Agent Notes

- Do not modify or remove third-party folders unless explicitly requested.
- FFmpeg xcframeworks are pre-built from the repository's pinned FFmpeg 6.1.6
  GnuTLS/SecTrust recipe. Build provenance and license notices live under
  `IRFFMpeg/Provenance/`; do not rebuild the binaries in CI.
