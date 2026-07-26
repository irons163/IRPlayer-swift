# AGENTS.md — FFmpeg

FFmpeg decode pipeline — format context, decoders, frames, and utilities.

## Files

| File                         | Purpose                                              |
|------------------------------|------------------------------------------------------|
| `IRFFFormatContext.swift`    | Serialized input-generation lifecycle facade         |
| `IRFFFormatContextBuilder.swift` | FFmpeg input/codec generation construction       |
| `IRFFFormatContextResources.swift` | C-resource and interrupt-callback ownership     |
| `IRFFFormatContextSemantics.swift` | Pure timing, track, and selection semantics      |
| `IRFFDecoder.swift`          | Decoder orchestration (coordinates audio + video)    |
| `IRFFDecoderCollaboratorSession.swift` | Weak collaborator generation and revoke gate |
| `IRFFAudioDecoder.swift`     | Audio packet → audio frame decoding                  |
| `IRFFAudioResampleSession.swift` | Owned resampler and managed sample scratch       |
| `IRFFVideoDecoder.swift`     | Video packet → video frame decoding                  |
| `IRFFDecodeAdmission.swift`  | Shared bounded decode/output admission model         |
| `IRFFCustomVideoDecoding.swift` | Immutable public custom-decode values and token  |
| `IRFFDecodeFrame.swift`      | Shared owned AVFrame scratch resource                |
| `IRFFVideoToolBox.swift`     | Hardware-accelerated decoding via VideoToolBox        |
| `IRFFVideoToolBoxSession.swift` | VideoToolbox generations, leases, and callbacks    |
| `IRFFVideoToolBoxH264.swift` | AVCC, NAL, and Core Media payload construction        |
| `IRFFVideoInput.swift`       | Custom video input for direct frame injection        |
| `IRFFTrack.swift`            | Audio/video track metadata                           |
| `IRFFDictionary.swift`       | Owned options and borrowed metadata conversion       |
| `IRFFMetadata.swift`         | Immutable parsed stream metadata                     |
| `IRFFTools.swift`            | FFmpeg utilities, log formatting, and gated diagnostics |

## Subdirectory

- `Frame/` — Frame data models and queue management.

## Agent Notes

- `IRFFFormatContext` opens media and provides packet streams.
- Keep FFmpeg variadic log formatting and its compile-time diagnostic gate in
  `IRFFTools`; enabled output must use the public library logger, while
  disabled output must not evaluate message autoclosures.
- Publish one complete format/codec generation only after at least one usable
  audio or video track opens. Do not expose partially initialized FFmpeg
  pointers.
- Keep format setup, packet reads, seeks, track replacement, and destruction
  serialized through the format-context operation gate.
- `destroy()` requests interruption before waiting for the operation gate,
  then transitions terminally to closed.
- FFmpeg interrupt callbacks use a separately retained
  `IRFFFormatContextInterruptState`; never point `opaque` at an unretained
  facade.
- Every context returned by `avcodec_alloc_context3` must be destroyed with
  `avcodec_free_context`. Do not replace it with `avcodec_close`, which leaves
  the `AVCodecContext` allocation alive.
- Close the input context before releasing its retained callback reference.
- Mutable FFmpeg option dictionaries must have one `IRFFDictionary` owner;
  pass its pointer only through the fixed-result scoped borrow.
- Format and stream metadata dictionaries are borrowed. Convert them to Swift
  values without freeing or retaining their FFmpeg pointers.
- Each successful format read publishes one `IRFFPacket` owner. Audio consumes
  and closes it synchronously; video transfers it through the typed packet
  queue and closes it after scoped decode.
- Audio and video decoder scratch frames must use `IRFFDecodeFrame`; pair
  `av_frame_alloc` only with `av_frame_free` inside that owner.
- Audio resampling must use `IRFFAudioResampleSession`. Keep `SwrContext`,
  `extended_data`, and managed Int16 scratch access inside its scoped
  conversion operation.
- `IRFFDecoder` coordinates the decode loop across audio and video.
- Keep seek range validation, resume targeting, and seek-completion transitions
  on `IRFFDecoder`; read-loop states may consume those owner semantics but must
  not recreate them.
- Keep audio, buffering, packet-routing, and display timing transitions on
  `IRFFDecoder`; read/display loop states translate those decisions into
  actions but do not own a parallel policy layer.
- Keep sample/resample arithmetic on `IRFFAudioDecoder` and frame/decode timing
  on `IRFFVideoDecoder`. Both use `IRFFDecodeResult` for shared FFmpeg
  send/receive result classification.
- Keep error translation and stream rational fallback semantics directly in
  `IRFFTools`; all numeric narrowing from Swift values must be exact.
- Delegate, custom source, video output, and audio output belong to one
  `IRFFDecoderCollaboratorSession` generation. Install a complete generation
  before opening, and use one terminal revoke before resource teardown.
- Video delivery is serialized with collaborator revocation so replacement
  cannot return while an already-admitted old frame is still entering its
  output. Delegate and audio callbacks use synchronized strong snapshots
  outside the lock; never cross into the player executor while holding the
  collaborator gate.
- Coordinate source snapshot/install/update/revoke through the collaborator
  owner and `IRFFDecoderSession`; post-revoke compatibility setters must never
  resurrect a decoder.
- `IRFFVideoToolBox` wraps Apple's VideoToolBox for hardware H.264 decoding.
- Keep VideoToolbox setup, decode, reset, and close serialized through the
  facade operation gate.
- Publish a complete `VTDecompressionSession` generation through
  `IRFFVideoToolBoxSession`; never store a separate setup token or partially
  initialized resource fields.
- Reset is repeatable, close is terminal, and stale setup tickets must not
  publish after either transition.
- Active generation leases must drain before waiting for frames, invalidating
  the session, and releasing its callback reference.
- The VideoToolbox callback context is retained per session generation. Do not
  point callbacks at an unretained facade or release the context before session
  invalidation.
- Decode opts into VideoToolbox temporal processing, but not asynchronous
  decompression, so B-frames may be emitted in display order. Temporal callbacks
  may still arrive after `DecodeFrame` returns: retain them in the generation
  mailbox across packets, wait before the end-of-stream drain, and never release
  the callback reference before wait and session invalidation complete.
- Never block future temporal `DecodeFrame` input on frame credits, and never
  call `FinishDelayedFrames` or its wait barrier midstream. A future B-frame may
  precede an already-decoded reference frame in display order, so forcing that
  reference frame out early cannot be repaired after display dequeues it.
  Delayed submissions are codec-owned reorder buffering; drain them only at EOS
  or teardown with the documented wait fence.
- Preserve callback `VTDecodeInfoFlags`; interrupted or dropped callbacks are
  consumed without publishing their image buffers because VideoToolbox may
  attach an all-black buffer to an interrupted frame.
- Each temporal decode submission owns a retained `sourceFrameRefCon` containing
  only packet timing values. Consume it exactly once in the callback, release it
  immediately when `DecodeFrame` returns an error, and use those values—not the
  packet that happened to trigger a later mailbox drain—for invalid callback
  timestamp or duration fallback.
- `IRFFVideoInput` allows bypassing the decode pipeline entirely for custom
  frame sources. Build one immutable `IRFFVideoCodecDescriptor` for the
  decoder generation, then route each borrowed packet through the
  allocation-free `IRFFVideoPacketDescriptor`. Never expose `AVPacket`,
  `AVCodecContext`, or another borrowed pointer across that public boundary.
- Copy `IRFFCompressedVideoPacket` payload and side-data bytes only after
  `shouldHandle` opts in. The accepted packet owns its storage so callers may
  retain it or send it to asynchronous decode work.
- Every accepted custom packet owns one bounded reservation and one one-shot
  completion. `.deferred` work must retain the token; token deinit, explicit
  drop, seek/stop invalidation, or terminal error resolves the reservation
  exactly once and reclaims every rejected or late frame.
- Keep software, VideoToolbox, external, and custom outputs in one admission
  ledger. Check-and-reserve must be atomic; do not infer unique occupancy by
  adding or taking the maximum of overlapping pool and queue counts.
- Same-generation flush must fail without mutation while a decoder worker is
  active. Generation-advancing invalidation cancels old work and wakes all
  capacity and deferred-completion waiters.
- The first terminal decode error must reject new packet/output/custom
  admission, cancel every pending completion, and publish exactly once to the
  internal decoder delegate bridge. Keep that bridge publication inside the
  recursive decoder transition gate so seek/close cannot overtake the winning
  commit, but never synchronously wait for the player executor there:
  off-executor bridges enqueue and revalidate token, decoder identity, and
  event fence when they run. The bridge is an ordering boundary, not permission
  to run arbitrary user callbacks while decoder/custom locks are held.
- Custom source and output bindings are synchronized weak references. Detaching
  a decoder generation must propagate the nil source into an installed video
  decoder before teardown; an input must never own its display/decoder target.
- Tests: `IRFFFormatContextTests.swift`,
  `IRFFFormatContextResourcesTests.swift`, `IRFFAudioDecoderTests.swift`,
  `IRFFAudioResampleSessionTests.swift`, `IRFFDecodeFrameTests.swift`,
  `IRFFVideoDecoderTests.swift`, `IRFFVideoToolBoxTests.swift`,
  `IRFFVideoToolBoxSessionTests.swift`, `IRFFToolsTests.swift`,
  `IRFFDecoderCollaboratorSessionTests.swift`,
  `IRFFDictionaryTests.swift`, `IRFFTrackTests.swift`,
  `IRFFMetadataTests.swift`, `IRFFVideoInputTests.swift`, and
  `IRFFDecodeAdmissionTests.swift`, `IRFFDecoderOperationTests.swift`.
