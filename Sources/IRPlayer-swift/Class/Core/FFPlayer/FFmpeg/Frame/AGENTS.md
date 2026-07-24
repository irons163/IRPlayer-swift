# AGENTS.md — Frame

Frame data models and queue management for the FFmpeg decode pipeline.

## Files

| File                          | Purpose                                             |
|-------------------------------|-----------------------------------------------------|
| `IRFFFrame.swift`             | Synchronized lifecycle and transport metadata value |
| `IRFFVideoFrame.swift`        | Atomic video-dimension value and base frame          |
| `IRFFAVYUVVideoFrame.swift`   | Software-decoded YUV frame generation owner         |
| `IRFFYUVPlaneStorage.swift`   | Managed I420 layouts, storage, and COW snapshots    |
| `IRFFCVYUVVideoFrame.swift`   | Hardware-decoded YUV video frame (CVPixelBuffer)    |
| `IRVideoFrameRGB.swift`       | Immutable checked RGB24/BGRA32 frame generation      |
| `IRFFAudioFrame.swift`        | Decoded audio frame                                 |
| `IRFFFramePool.swift`         | Explicit frame lease/reuse/close owner               |
| `IRFFFrameQueue.swift`        | Immutable-entry decoded-frame transfer owner         |
| `IRFFPacket.swift`            | Single-owner FFmpeg packet lifecycle                |
| `IRFFPacketQueue.swift`       | Thread-safe queue for undecoded packets             |

## Agent Notes

- `IRFFAVYUVVideoFrame` is used with software FFmpeg decoding.
- It copies all three I420 planes into one checked managed generation. Keep
  width, height, chroma dimensions, pixel format, byte counts, and plane bytes
  coherent at publication.
- Consumers must use `planeSnapshot()`. Raw plane addresses may exist only
  inside `IRFFYUVPlaneSnapshot.withUnsafePlaneBytes`; do not restore
  `channelPixels` or luma/chroma pointer getters.
- Source line sizes must cover their plane widths. Preserve ceiling chroma
  dimensions for odd I420 frames and checked byte arithmetic.
- Flush revokes active data but retains reusable managed capacity. Existing
  snapshots remain immutable through Swift copy-on-write.
- `IRFFCVYUVVideoFrame` is used with VideoToolBox hardware decoding (CVPixelBuffer).
- Video dimensions are published as one `IRFFVideoDimensions` value. Generic
  custom frames use `setDimensions(width:height:)`; first-party consumers must
  use `dimensionSnapshot()` rather than assembling a size from separate reads.
- `IRVideoFrameRGB` requires width, height, explicit `IRRGBPixelFormat`,
  row stride, and data at construction. Keep its source and Metal upload bytes
  immutable and validated; never infer RGB24 versus BGRA32 from stride.
- Preparing a software-YUV frame for pool reuse must revoke its active plane
  generation while preserving managed capacity.
- `IRFFFrame` synchronizes delegate, playing state, position, duration, and
  size. Queue admission must use its coherent transport snapshot.
- `IRFFFramePool` reduces allocation churn with one exact partition of owned
  available, leased, and playing identities. Only `leaseFrame()` creates or
  transfers a lease. Keep factory validation, reusable flush, and terminal
  close semantics intact.
- Pool diagnostics are the only supported way to inspect buckets; do not
  expose mutable sets or unlocked count fields.
- Every ready `AVPacket` reference must be owned by one `IRFFPacket`. Borrow
  raw packet state only through its scoped operation and close it exactly once.
- The video packet queue transfers `IRFFPacket` owners across threads. Keep
  packet, flush, and closed as typed items; never encode control state in
  `AVPacket.data` or `stream_index`.
- `IRFFFrameQueue` captures immutable position/duration/size entries when
  ownership transfers. Never recalculate accounting from a mutable frame.
- Synchronous frame dequeue waits on the condition and close broadcasts to all
  waiters. Flush and close cancel drained frames outside the queue lock so
  pooled ownership returns without callback reentrancy.
- Duplicate queue identity is rejected without cancellation because the queue
  already owns that frame. Overflow and post-close offers are cancelled.
- `IRFFFrameQueue` and `IRFFPacketQueue` are producer-consumer owners —
  threading, wakeup, and terminal lifecycle behavior are critical.
- `IRFFAudioFrame` owns decoded PCM in managed contiguous storage. Keep
  mutation inside `withMutableSamples`, reads inside snapshots or checked
  copies, and never restore a stored or escaping sample pointer.
- Grow audio sample storage on the decoder side. The real-time render callback
  may copy active bytes but must not resize frame storage.
- Tests: `IRFFAudioFrameTests.swift`, `IRFFAVYUVVideoFrameTests.swift`,
  `IRVideoFrameRGBTests.swift`, `IRFFFramePoolTests.swift`,
  `IRFFFrameQueueTests.swift`,
  `IRFFPacketTests.swift`, and `IRFFPacketQueueTests.swift`.
