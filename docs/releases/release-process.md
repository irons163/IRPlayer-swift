# Release acceptance and delivery

IRPlayer releases use the same automated acceptance suite for pull requests,
branch builds, and tagged releases. A release is publishable only when every
gate below passes.

## Acceptance gates

The reusable `Acceptance` workflow runs two macOS jobs in parallel:

1. `Framework build and tests`
   - validates the Swift package manifest;
   - performs a Release build for a generic iOS device without code signing;
   - runs the complete `IRPlayer-swiftTests` suite on an available iPhone
     simulator.
2. `Eight-mode playback UI tests`
   - runs the demo app's eight playback/rendering regression tests;
   - covers AVPlayer normal, VR, VR Box, FFmpeg software and hardware,
     fisheye, panorama, and multi-view playback.

The final `Release acceptance` job fails unless both jobs succeed. Each macOS
job uploads its logs and `.xcresult` bundle for 14 days, including failed runs.

Run the identical suite locally:

```bash
Scripts/ci/run-acceptance.sh all
```

To choose a particular installed simulator:

```bash
IRPLAYER_SIMULATOR_ID="<simulator-udid>" Scripts/ci/run-acceptance.sh all
```

## Continuous integration

`.github/workflows/ci.yml` runs acceptance for:

- every pull request targeting `main`;
- every push to `main` or a `codex/**` branch;
- manual runs from the Actions page.

After the first successful run, configure the `main` branch ruleset to require
the final check whose name ends in `Release acceptance`. Also require branches
to be up to date before merging. This makes the workflow an enforced merge
gate instead of an informational check.

## Continuous delivery

`.github/workflows/release.yml` reacts to a pushed version tag. Supported tag
forms include `2.0`, `2.0.1`, `v2.0.1`, and prereleases such as
`2.1.0-rc.1`.

The workflow:

1. rejects malformed tags and tags whose commit is not reachable from `main`;
2. runs the complete reusable acceptance workflow against the tagged commit;
3. creates a GitHub Release only after every gate succeeds;
4. marks tags containing a prerelease suffix as prereleases.

The library is distributed through Swift Package Manager, so the immutable Git
tag and GitHub's generated source archives are the release artifacts. No
repository secret is required; the publish job alone receives
`contents: write` permission through `GITHUB_TOKEN`.

Release from an accepted `main` commit:

```bash
git switch main
git pull --ff-only
git tag -a 2.0.1 -m "IRPlayer 2.0.1"
git push origin 2.0.1
```

Do not move or reuse a published version tag. If release acceptance fails, fix
the issue on `main` and create a new version tag.
