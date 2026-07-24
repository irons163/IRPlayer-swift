# AGENTS.md — Frame

Frame data models and queue management for the FFmpeg decode pipeline.

## Files

| File                          | Purpose                                             |
|-------------------------------|-----------------------------------------------------|
| `IRFFFrame.swift`             | Base frame protocol/class                           |
| `IRFFVideoFrame.swift`        | Base video frame                                    |
| `IRFFAVYUVVideoFrame.swift`   | Software-decoded YUV frame generation owner         |
| `IRFFYUVPlaneStorage.swift`   | Managed I420 layouts, storage, and COW snapshots    |
| `IRFFCVYUVVideoFrame.swift`   | Hardware-decoded YUV video frame (CVPixelBuffer)    |
| `IRVideoFrameRGB.swift`       | RGB video frame                                     |
| `IRFFAudioFrame.swift`        | Decoded audio frame                                 |
| `IRFFFramePool.swift`         | Object pool for frame reuse to reduce allocations   |
| `IRFFFrameQueue.swift`        | Thread-safe queue for decoded frames                |
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
- `IRFFFramePool` reduces allocation churn by reusing frame objects.
- Every ready `AVPacket` reference must be owned by one `IRFFPacket`. Borrow
  raw packet state only through its scoped operation and close it exactly once.
- The video packet queue transfers `IRFFPacket` owners across threads. Keep
  packet, flush, and closed as typed items; never encode control state in
  `AVPacket.data` or `stream_index`.
- `IRFFFrameQueue` and `IRFFPacketQueue` are producer-consumer queues —
  threading is critical.
- `IRFFAudioFrame` owns decoded PCM in managed contiguous storage. Keep
  mutation inside `withMutableSamples`, reads inside snapshots or checked
  copies, and never restore a stored or escaping sample pointer.
- Grow audio sample storage on the decoder side. The real-time render callback
  may copy active bytes but must not resize frame storage.
- Tests: `IRFFAudioFrameTests.swift`, `IRFFAVYUVVideoFrameTests.swift`,
  `IRFFFramePoolTests.swift`, `IRFFFrameQueueTests.swift`,
  `IRFFPacketTests.swift`, and `IRFFPacketQueueTests.swift`.
