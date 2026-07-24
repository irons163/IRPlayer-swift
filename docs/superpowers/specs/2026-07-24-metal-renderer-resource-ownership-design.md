# Metal Renderer Resource Ownership Design

## Summary

`IRGLMetalSurfaceSession` publishes a surface only after a device, command
queue, Core Image context, and renderer exist. The renderer itself does not
currently honor the same complete-generation rule: it succeeds after creating
only its own command queue, while the Core Video texture cache, shader library,
ten render pipelines, and three quad buffers can each remain `nil`.

Replace that partial initialization with one immutable
`IRMetalRendererResources` generation. Resource construction is injectable and
returns a typed failure for the exact missing cache, library, function,
pipeline, or quad buffer. A renderer is created only from a complete
generation, and the surface passes its command queue into that renderer so all
work belonging to one surface generation is ordered on one queue.

Move the mutable distortion offscreen texture and its separately stored size
into a synchronized `IRMetalDistortionTargetSession`. It publishes one coherent
texture generation keyed by canonical pixel dimensions, preserves the prior
complete target when replacement fails, and has explicit reset and terminal
close behavior.

## Problems

- `IRMetalRenderer.init` returns a usable object even when its texture cache,
  shader library, pipelines, or vertex buffers are missing.
- Render paths discover partial initialization late through optional guards,
  usually returning `false` without identifying the construction failure.
- Tests manufacture impossible runtime states by mutating renderer pipelines
  to `nil`, preserving the partial-resource model instead of testing bootstrap
  failures.
- A surface generation creates one command queue while its renderer creates a
  second queue. Clear, image, snapshot, and renderer work therefore do not
  share one explicit ordering domain.
- The distortion target texture and requested `CGSize` are separate mutable
  fields. Fractionally different sizes that map to the same pixel dimensions
  also rebuild an equivalent texture.
- Distortion target replacement, failure, reset, close, and concurrent access
  have no focused lifecycle boundary or diagnostics.
- `IRMetalRendererDistortionPolicy` is a forwarding-only policy beside the
  mutable state it describes.

## Goals

- Build every required renderer resource locally before publishing any
  renderer.
- Make renderer pipelines, texture cache, and quad buffers immutable and
  non-optional after construction.
- Return an exact, equatable bootstrap failure for every resource stage.
- Keep shader names, pipeline kinds, and quad ranges explicit and testable.
- Use the surface generation's command queue inside its renderer.
- Preserve the convenience renderer initializer for internal adapters and
  direct tests while applying the same complete-resource invariant.
- Own distortion target texture, dimensions, generation, and lifecycle in one
  synchronized session.
- Reuse a distortion target for equivalent canonical pixel sizes.
- Preserve the last complete distortion target when invalid input or
  replacement allocation fails.
- Make distortion reset repeatable and close terminal.
- Consolidate distortion size and scissor validation into its domain owner.
- Preserve all successful render-mode and pixel-format behavior.

## Non-Goals

- Change the public player or display API.
- Change shader source, color conversion, mesh geometry, viewport semantics,
  or visual output.
- Add cross-frame decoded texture caching.
- Rebuild pipelines after a renderer has been published.
- Recover a partially capable renderer by disabling individual modes.
- Change the existing render executor or command-completion resource owner.
- Consolidate unrelated geometry, scale, or pixel-format policy files.

## Components

### `IRMetalRendererResources`

One immutable generation contains:

- a `CVMetalTextureCache`;
- all ten required render pipeline states:
  - NV12, I420, and RGB 2D;
  - NV12, I420, and RGB mesh;
  - NV12, I420, and RGB fish2pano;
  - distortion;
- full, left-eye, and right-eye quad buffers; and
- immutable diagnostics reporting the complete resource counts.

Construction uses `IRMetalRendererResourceDependencies`, which isolates:

- Core Video texture-cache creation;
- shader-library loading;
- named shader-function lookup;
- typed pipeline creation; and
- typed quad-buffer creation.

The builder creates local values in dependency order and returns
`Result<IRMetalRendererResources, IRMetalRendererBuildFailure>`. No partial
resource object escapes.

### Renderer Bootstrap

`IRMetalRenderer.make(device:commandQueue:dependencies:)` is the typed factory.
It publishes a renderer only after resource construction succeeds. The
renderer exposes read-only, non-optional resource access used by existing
render paths.

`IRMetalRenderer.init?(device:)` remains as an internal convenience. It creates
one command queue and then uses the same resource builder; failure at either
stage returns `nil`.

Renderer construction itself does not create another queue when a caller
already owns one.

### Surface Integration

`IRGLMetalSurfaceDependencies.makeRenderer` accepts both the selected device
and the already-created command queue and returns the typed renderer result.
`IRGLMetalSurfaceFailure.renderer` retains the exact renderer bootstrap
failure.

The surface still publishes device, queue, Core Image context, renderer, and
layer attachment atomically. A ready surface guarantees that
`resources.commandQueue === resources.renderer.commandQueue`.

### `IRMetalDistortionTargetSession`

The target session owns an optional immutable generation containing:

- canonical integer pixel width and height; and
- the matching render-target/shader-read texture.

Its phases are `idle`, `ready`, and `closed`. All phase, generation, counters,
and target mutations are protected by one lock.

For each request:

1. reject work after close;
2. validate and canonicalize the requested drawable size;
3. reuse the current generation when its pixel dimensions match;
4. build a replacement texture locally; and
5. publish the replacement atomically only after allocation succeeds.

Invalid input or allocation failure increments failure diagnostics and leaves
the prior complete generation intact. `reset` clears a live generation and
returns to `idle`; `close` clears it and is terminal. Deinitialization closes
the session.

Distortion texture-size and scissor calculations move into this domain, and
the forwarding-only `IRMetalRendererDistortionPolicy` is removed.

## Invariants

- A published renderer has exactly one texture cache, ten pipelines, and three
  quad buffers.
- A renderer resource field never transitions from present to absent.
- A renderer bootstrap failure publishes no renderer.
- The reported failure identifies the first required resource that could not
  be built.
- One surface generation uses one command queue for all Metal work.
- Surface resources remain complete-or-unavailable.
- A distortion target generation contains matching dimensions and texture.
- Equivalent canonical pixel sizes reuse one target generation.
- Failed distortion replacement never overwrites a complete prior target.
- Distortion close is terminal and post-close requests cannot publish.
- Successful render semantics remain unchanged for 2D, VR, fisheye,
  fish2pano, distortion, and multi4P.

## Testing

- Complete system renderer-resource construction and diagnostics.
- Missing texture cache and shader library.
- Exact missing shader-function name.
- Exact failed pipeline kind.
- Exact failed quad-buffer range.
- No later-stage construction after an earlier-stage failure.
- Renderer factory uses the exact caller-provided command queue.
- Surface reports typed renderer failure without partial publication.
- Ready surface shares its queue with the renderer.
- Distortion invalid-size and allocation-failure preservation.
- Same canonical size reuse and changed-size replacement.
- Reset, terminal close, deinit, and concurrent request behavior.
- Existing NV12, BGRA, I420, RGB, mesh, fish2pano, distortion, command
  resource, surface, render-state, and strategy behavior.

## Acceptance Criteria

- No mutable optional renderer cache, pipeline, or quad-buffer fields remain.
- No renderer builds a second queue for a prepared surface.
- Every bootstrap failure is deterministic and covered by a focused test.
- Distortion target state has one explicit synchronized owner and coherent
  diagnostics.
- The forwarding-only distortion policy is removed.
- Focused tests, Thread Sanitizer, integration tests, the full simulator suite,
  and a generic iOS device build pass.
