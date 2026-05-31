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
- `IRFFFramePool` reduces GC pressure by reusing frame objects.
- `IRFFFrameQueue` and `IRFFPacketQueue` are producer-consumer queues — threading is critical.
- Tests: `IRFFAVYUVVideoFrameTests.swift`, `IRFFFramePoolTests.swift`, `IRFFFrameQueueTests.swift`, `IRFFPacketQueueTests.swift`.
