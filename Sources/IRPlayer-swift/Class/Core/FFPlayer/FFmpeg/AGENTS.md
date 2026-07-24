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
| `IRFFDecodeFrame.swift`      | Shared owned AVFrame scratch resource                |
| `IRFFVideoToolBox.swift`     | Hardware-accelerated decoding via VideoToolBox        |
| `IRFFVideoToolBoxSession.swift` | VideoToolbox generations, leases, and callbacks    |
| `IRFFVideoToolBoxH264.swift` | AVCC, NAL, and Core Media payload construction        |
| `IRFFVideoInput.swift`       | Custom video input for direct frame injection        |
| `IRFFTrack.swift`            | Audio/video track metadata                           |
| `IRFFDictionary.swift`       | Owned options and borrowed metadata conversion       |
| `IRFFMetadata.swift`         | Immutable parsed stream metadata                     |
| `IRFFTools.swift`            | FFmpeg utility functions                             |

## Subdirectory

- `Frame/` — Frame data models and queue management.

## Agent Notes

- `IRFFFormatContext` opens media and provides packet streams.
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
- Decode currently uses empty Videotoolbox flags and depends on the documented
  synchronous callback-before-return contract. If async or temporal flags are
  introduced, redesign result correlation before enabling them.
- `IRFFVideoInput` allows bypassing the decode pipeline entirely for custom
  frame sources. Its callbacks receive only immutable
  `IRFFVideoCodecDescriptor`, `IRFFVideoDecoderInfo`, and
  `IRFFCompressedVideoPacket` values; never expose borrowed `AVPacket` or
  `AVCodecContext` pointers across that public boundary.
- Build one custom packet value while the internal packet borrow is active.
  The value must own payload and side-data bytes so callers may retain it or
  send it to asynchronous decode work.
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
  `IRFFDecoderOperationTests.swift`.
