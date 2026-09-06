# FFmpeg n6.1.6 GnuTLS/SecTrust provenance

This directory accompanies the exact XCFrameworks in `../../Libs`.

- `source-and-toolchain.txt`, `patches.manifest`, and `patches/` identify the
  pinned source, toolchain observation, and immutable five-patch set.
- `slices/` contains each target's dependency and FFmpeg inputs,
  configuration, fingerprints, and installed dylib hashes.
- `verification-recipes/` preserves the original binary-build recipe, the
  corrected package-verification recipe, and the metadata-hardening recipe.
  Read their adjacent provenance records before attributing a role to them.
- `installed-xcframework-regular-files.sha256` and
  `installed-xcframework-symlinks.txt` describe the checked-in `Libs/` tree.
- `candidate-package-artifact-*` preserves the sealed candidate package's
  broader manifest. Its paths include package metadata and are historical
  package evidence, not a manifest to run from this relocated directory.
- `bundle-id-amendment/` records the bounded post-build correction from the
  underscore-containing identifier to
  `org.irplayer.ffmpeg.n6-1-6.<library>`, the ad-hoc re-signing of all 21
  embedded frameworks, and code-sign-independent before/after identities.
  Its historical manifests preserve the seal and installed inventories from
  before that amendment; the top-level manifests describe the installed,
  corrected frameworks.
- `licenses/` and `license-sha256sums.txt` contain the distributed notices.

The recorded re-verification transcript is new independent evidence. It does
not reconstruct the stdout lost during the earlier failed audit-harness
attempt. Temporary build-root paths in historical logs identify the reviewed
local build and are not maintained as reusable repository commands.

To verify the checked-in regular files, run from `IRFFMpeg/Libs`:

~~~sh
shasum -a 256 -c ../Provenance/ffmpeg-n6.1.6-gnutls-sectrust/installed-xcframework-regular-files.sha256
~~~

Symlink targets require complete inventory comparison rather than dereferenced
file hashes; `installed-xcframework-symlinks.txt` records all 28 raw targets.
All 21 framework signatures and bundle identifiers are enumerated in
`bundle-id-amendment/installed-validation.log`.
