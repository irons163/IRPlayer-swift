import Foundation

protocol IRFFAudioFrameSource: AnyObject {
    func fetchAudioFrame() -> IRFFAudioRenderLease?
    func finishAudioFrame(_ identifier: ObjectIdentifier) -> Bool
    func finishAudioFrameSynchronously(
        _ identifier: ObjectIdentifier
    ) -> Bool
}

extension IRFFAudioFrameSource {
    func finishAudioFrame(_ identifier: ObjectIdentifier) -> Bool {
        true
    }

    func finishAudioFrameSynchronously(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        finishAudioFrame(identifier)
    }
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
    // Keep the lease owner alive until every callback-owned frame has been
    // acknowledged. Teardown explicitly detaches this reference before the
    // decoder session is closed, so there is no ownership cycle.
    private var source: (any IRFFAudioFrameSource)?
    private var storedCurrentLease: IRFFAudioRenderLease?
    private var pendingFinishedFrameID: ObjectIdentifier?
    private var pendingFinishedSource:
        (any IRFFAudioFrameSource)?
    private var enabled = false

    var diagnostics: Diagnostics {
        renderLock.lock()
        defer { renderLock.unlock() }
        return Diagnostics(
            enabled: enabled,
            hasSource: source != nil,
            hasCurrentFrame: storedCurrentLease != nil
        )
    }

    var currentFrame: IRFFAudioFrame? {
        renderLock.lock()
        defer { renderLock.unlock() }
        return storedCurrentLease?.frame
    }

    func attachSource(_ source: (any IRFFAudioFrameSource)?) {
        renderLock.lock()
        if self.source !== source ||
            (source == nil && storedCurrentLease != nil) {
            guard finishCurrentFrameLocked(
                waitForAcknowledgment: true
            ) else {
                renderLock.unlock()
                return
            }
        }
        self.source = source
        renderLock.unlock()
    }

    func setEnabled(_ enabled: Bool) {
        renderLock.lock()
        self.enabled = enabled
        renderLock.unlock()
    }

    /// Stops admission, waits for any active callback to leave, and
    /// synchronously returns the callback-owned frame before decoder teardown.
    func suspendAndDrain() {
        renderLock.lock()
        enabled = false
        _ = finishCurrentFrameLocked(
            waitForAcknowledgment: true
        )
        renderLock.unlock()
    }

    func replaceCurrentFrame(_ frame: IRFFAudioFrame?) {
        let replacement = frame.map {
            IRFFAudioRenderLease(
                frame: $0,
                byteCount: $0.size,
                outputOffset: $0.outputOffset
            )
        }
        renderLock.lock()
        if storedCurrentLease?.frame !== frame {
            guard finishCurrentFrameLocked(
                waitForAcknowledgment: true
            ) else {
                renderLock.unlock()
                return
            }
        }
        storedCurrentLease = replacement
        renderLock.unlock()
    }

    func reset() {
        renderLock.lock()
        enabled = false
        if finishCurrentFrameLocked(
            waitForAcknowledgment: true
        ) {
            source = nil
        }
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
        guard acknowledgePendingFrameLocked(
            waitForAcknowledgment: false
        ) else {
            return
        }

        var remainingFrames = numberOfFrames
        var currentOutput = outputData

        while remainingFrames > 0 {
            if storedCurrentLease == nil {
                storedCurrentLease = source?.fetchAudioFrame()
            }

            guard var lease = storedCurrentLease,
                  let plan = Self.copyPlan(
                    frameSize: lease.byteCount,
                    outputOffset: lease.outputOffset,
                    remainingFrames: remainingFrames,
                    numberOfChannels: numberOfChannels
                  ) else {
                _ = finishCurrentFrameLocked(
                    waitForAcknowledgment: false
                )
                return
            }

            guard lease.frame.copySamples(
                to: currentOutput,
                byteOffset: lease.outputOffset,
                byteCount: plan.bytesToCopy,
                availableByteCount: lease.byteCount
            ) else {
                _ = finishCurrentFrameLocked(
                    waitForAcknowledgment: false
                )
                return
            }

            remainingFrames -= UInt32(plan.framesToCopy)
            currentOutput = currentOutput.advanced(
                by: plan.framesToCopy * Int(numberOfChannels)
            )

            if plan.hasRemainingFrameBytes {
                lease.outputOffset += plan.bytesToCopy
                storedCurrentLease = lease
            } else {
                guard finishCurrentFrameLocked(
                    waitForAcknowledgment: false
                ) else {
                    return
                }
            }
        }
    }

    @discardableResult
    private func finishCurrentFrameLocked(
        waitForAcknowledgment: Bool
    ) -> Bool {
        guard acknowledgePendingFrameLocked(
            waitForAcknowledgment:
                waitForAcknowledgment
        ) else {
            return false
        }
        guard let lease = storedCurrentLease else {
            return true
        }
        let identifier = ObjectIdentifier(lease.frame)
        storedCurrentLease = nil
        guard acknowledge(
            identifier,
            from: source,
            waitForAcknowledgment:
                waitForAcknowledgment
        ) else {
            pendingFinishedFrameID = identifier
            pendingFinishedSource = source
            return false
        }
        return true
    }

    private func acknowledgePendingFrameLocked(
        waitForAcknowledgment: Bool
    ) -> Bool {
        guard let identifier = pendingFinishedFrameID else {
            return true
        }
        guard acknowledge(
            identifier,
            from: pendingFinishedSource,
            waitForAcknowledgment:
                waitForAcknowledgment
        ) else {
            return false
        }
        pendingFinishedFrameID = nil
        pendingFinishedSource = nil
        return true
    }

    private func acknowledge(
        _ identifier: ObjectIdentifier,
        from source: (any IRFFAudioFrameSource)?,
        waitForAcknowledgment: Bool
    ) -> Bool {
        guard let source else { return true }
        if waitForAcknowledgment {
            return source.finishAudioFrameSynchronously(
                identifier
            )
        }
        return source.finishAudioFrame(identifier)
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
