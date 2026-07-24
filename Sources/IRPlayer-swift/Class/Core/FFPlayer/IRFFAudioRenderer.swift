import Foundation

protocol IRFFAudioFrameSource: AnyObject {
    func fetchAudioFrame() -> IRFFAudioFrame?
}

extension IRFFDecoder: IRFFAudioFrameSource {}

final class IRFFAudioRenderer:
    IRAudioManagerDelegate,
    @unchecked Sendable
{
    struct CopyPlan: Equatable, Hashable, Sendable {
        let bytesToCopy: Int
        let framesToCopy: Int
        let hasRemainingFrameBytes: Bool
    }

    struct Diagnostics {
        let enabled: Bool
        let hasSource: Bool
        let hasCurrentFrame: Bool
    }

    private let renderLock = NSLock()
    private weak var source: (any IRFFAudioFrameSource)?
    private var storedCurrentFrame: IRFFAudioFrame?
    private var enabled = false

    var diagnostics: Diagnostics {
        renderLock.lock()
        defer { renderLock.unlock() }
        return Diagnostics(
            enabled: enabled,
            hasSource: source != nil,
            hasCurrentFrame: storedCurrentFrame != nil
        )
    }

    var currentFrame: IRFFAudioFrame? {
        renderLock.lock()
        defer { renderLock.unlock() }
        return storedCurrentFrame
    }

    func attachSource(_ source: (any IRFFAudioFrameSource)?) {
        renderLock.lock()
        if self.source !== source ||
            (source == nil && storedCurrentFrame != nil) {
            storedCurrentFrame?.stopPlaying()
            storedCurrentFrame = nil
        }
        self.source = source
        renderLock.unlock()
    }

    func setEnabled(_ enabled: Bool) {
        renderLock.lock()
        self.enabled = enabled
        renderLock.unlock()
    }

    func replaceCurrentFrame(_ frame: IRFFAudioFrame?) {
        renderLock.lock()
        if storedCurrentFrame !== frame {
            storedCurrentFrame?.stopPlaying()
        }
        storedCurrentFrame = frame
        renderLock.unlock()
    }

    func reset() {
        renderLock.lock()
        enabled = false
        source = nil
        storedCurrentFrame?.stopPlaying()
        storedCurrentFrame = nil
        renderLock.unlock()
    }

    func audioManager(
        _ audioManager: IRAudioManager,
        outputData: UnsafeMutablePointer<Float>,
        numberOfFrames: UInt32,
        numberOfChannels: UInt32
    ) {
        guard let byteCount = Self.silenceByteCount(
            numberOfFrames: numberOfFrames,
            numberOfChannels: numberOfChannels
        ) else {
            return
        }
        memset(outputData, 0, byteCount)

        guard renderLock.try() else { return }
        defer { renderLock.unlock() }
        guard enabled else { return }

        var remainingFrames = numberOfFrames
        var currentOutput = outputData

        while remainingFrames > 0 {
            if storedCurrentFrame == nil {
                storedCurrentFrame = source?.fetchAudioFrame()
                storedCurrentFrame?.startPlaying()
            }

            guard let frame = storedCurrentFrame,
                  let plan = Self.copyPlan(
                    frameSize: frame.size,
                    outputOffset: frame.outputOffset,
                    remainingFrames: remainingFrames,
                    numberOfChannels: numberOfChannels
                  ) else {
                storedCurrentFrame?.stopPlaying()
                storedCurrentFrame = nil
                return
            }

            guard frame.copySamples(
                to: currentOutput,
                byteOffset: frame.outputOffset,
                byteCount: plan.bytesToCopy
            ) else {
                frame.stopPlaying()
                storedCurrentFrame = nil
                return
            }

            remainingFrames -= UInt32(plan.framesToCopy)
            currentOutput = currentOutput.advanced(
                by: plan.framesToCopy * Int(numberOfChannels)
            )

            if plan.hasRemainingFrameBytes {
                frame.outputOffset += plan.bytesToCopy
            } else {
                frame.stopPlaying()
                storedCurrentFrame = nil
            }
        }
    }

    static func silenceByteCount(
        numberOfFrames: UInt32,
        numberOfChannels: UInt32
    ) -> Int? {
        guard let samples = IRAudioRenderContext.sampleCount(
            numberOfFrames: numberOfFrames,
            numberOfChannels: numberOfChannels
        ) else {
            return nil
        }
        let (bytes, overflow) = samples.multipliedReportingOverflow(
            by: MemoryLayout<Float>.stride
        )
        guard !overflow, bytes > 0 else { return nil }
        return bytes
    }

    static func copyPlan(
        frameSize: Int,
        outputOffset: Int,
        remainingFrames: UInt32,
        numberOfChannels: UInt32
    ) -> CopyPlan? {
        guard frameSize > 0,
              outputOffset >= 0,
              outputOffset <= frameSize,
              remainingFrames > 0,
              numberOfChannels > 0 else {
            return nil
        }

        let (bytesPerFrame, frameSizeOverflow) = Int(numberOfChannels)
            .multipliedReportingOverflow(
                by: MemoryLayout<Float>.stride
            )
        guard !frameSizeOverflow,
              bytesPerFrame > 0,
              outputOffset % bytesPerFrame == 0 else {
            return nil
        }

        let bytesLeft = frameSize - outputOffset
        guard bytesLeft > 0 else { return nil }
        let (requestedBytes, requestedOverflow) = Int(remainingFrames)
            .multipliedReportingOverflow(by: bytesPerFrame)
        guard !requestedOverflow else { return nil }

        let boundedBytes = min(requestedBytes, bytesLeft)
        let bytesToCopy = boundedBytes - (boundedBytes % bytesPerFrame)
        let framesToCopy = bytesToCopy / bytesPerFrame
        guard bytesToCopy > 0, framesToCopy > 0 else { return nil }

        return CopyPlan(
            bytesToCopy: bytesToCopy,
            framesToCopy: framesToCopy,
            hasRemainingFrameBytes: bytesToCopy < bytesLeft
        )
    }
}
