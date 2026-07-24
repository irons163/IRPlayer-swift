# AGENTS.md — Frame

Frame data models and queue management for the FFmpeg decode pipeline.

## Files

| File                          | Purpose                                             |
|-------------------------------|-----------------------------------------------------|
| `IRFFFrame.swift`             | Base frame protocol/class                           |
| `IRFFVideoFrame.swift`        | Base video frame                                    |
| `IRFFAVYUVVideoFrame.swift`   | Software-decoded YUV video frame (AVFrame-backed)   |
| `IRFFCVYUVVideoFrame.swift`   | Hardware-decoded YUV video frame (CVPixelBuffer)    |
| `IRVideoFrameRGB.swift`       | RGB video frame                                     |
| `IRFFAudioFrame.swift`        | Decoded audio frame                                 |
| `IRFFFramePool.swift`         | Object pool for frame reuse to reduce allocations   |
| `IRFFFrameQueue.swift`        | Thread-safe queue for decoded frames                |
| `IRFFPacketQueue.swift`       | Thread-safe queue for undecoded packets             |

## Agent Notes

- `IRFFAVYUVVideoFrame` is used with software FFmpeg decoding.
- `IRFFCVYUVVideoFrame` is used with VideoToolBox hardware decoding (CVPixelBuffer).
- `IRFFFramePool` reduces allocation churn by reusing frame objects.
- `IRFFFrameQueue` and `IRFFPacketQueue` are producer-consumer queues — threading is critical.
- `IRFFAudioFrame` owns decoded PCM in managed contiguous storage. Keep
  mutation inside `withMutableSamples`, reads inside snapshots or checked
  copies, and never restore a stored or escaping sample pointer.
- Grow audio sample storage on the decoder side. The real-time render callback
  may copy active bytes but must not resize frame storage.
- Tests: `IRFFAudioFrameTests.swift`, `IRFFAVYUVVideoFrameTests.swift`,
  `IRFFFramePoolTests.swift`, `IRFFFrameQueueTests.swift`, and
  `IRFFPacketQueueTests.swift`.
