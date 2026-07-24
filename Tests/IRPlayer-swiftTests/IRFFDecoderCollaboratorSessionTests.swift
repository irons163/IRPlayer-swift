import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDecoderCollaboratorSessionTests: XCTestCase {
    func testCompleteInstallReplacesOneCoherentWeakGeneration() {
        let initial = CollaboratorFixture()
        let session = IRFFDecoderCollaboratorSession(
            configuration: initial.configuration
        )

        XCTAssertEqual(
            session.diagnostics,
            .init(
                phase: .active,
                generation: 1,
                hasDelegate: true,
                hasSource: true,
                hasVideoOutput: true,
                hasAudioOutput: true,
                installCount: 1,
                revokeCount: 0,
                acceptedVideoDeliveryCount: 0,
                rejectedVideoDeliveryCount: 0,
                rejectedUpdateCount: 0
            )
        )
        XCTAssertTrue(session.snapshot.delegate === initial.delegate)
        XCTAssertTrue(session.snapshot.source === initial.source)
        XCTAssertTrue(
            session.snapshot.videoOutput === initial.videoOutput
        )
        XCTAssertTrue(
            session.snapshot.audioOutput === initial.audioOutput
        )

        let replacement = CollaboratorFixture()
        var synchronizedSource:
            IRFFVideoDecoderDataSource?
        XCTAssertTrue(
            session.install(
                replacement.configuration
            ) { snapshot in
                synchronizedSource = snapshot.source
                XCTAssertTrue(
                    snapshot.delegate === replacement.delegate
                )
                XCTAssertTrue(
                    snapshot.videoOutput === replacement.videoOutput
                )
                XCTAssertTrue(
                    snapshot.audioOutput === replacement.audioOutput
                )
            }
        )

        XCTAssertTrue(synchronizedSource === replacement.source)
        XCTAssertEqual(session.diagnostics.generation, 2)
        XCTAssertEqual(session.diagnostics.installCount, 2)
        XCTAssertTrue(session.snapshot.delegate === replacement.delegate)
        XCTAssertTrue(session.snapshot.source === replacement.source)
        XCTAssertTrue(
            session.snapshot.videoOutput === replacement.videoOutput
        )
        XCTAssertTrue(
            session.snapshot.audioOutput === replacement.audioOutput
        )
        XCTAssertEqual(
            session.withAudioOutput(default: 0) {
                $0.numberOfChannels
            },
            replacement.audioOutput.numberOfChannels
        )
    }

    func testBindingsDoNotExtendCollaboratorLifetime() {
        var fixture: CollaboratorFixture? = CollaboratorFixture()
        let delegate = CollaboratorWeakBox(fixture?.delegate)
        let source = CollaboratorWeakBox(fixture?.source)
        let videoOutput = CollaboratorWeakBox(
            fixture?.videoOutput
        )
        let audioOutput = CollaboratorWeakBox(
            fixture?.audioOutput
        )
        let session = IRFFDecoderCollaboratorSession(
            configuration: fixture!.configuration
        )

        fixture = nil

        XCTAssertNil(delegate.value)
        XCTAssertNil(source.value)
        XCTAssertNil(videoOutput.value)
        XCTAssertNil(audioOutput.value)
        XCTAssertFalse(session.diagnostics.hasDelegate)
        XCTAssertFalse(session.diagnostics.hasSource)
        XCTAssertFalse(session.diagnostics.hasVideoOutput)
        XCTAssertFalse(session.diagnostics.hasAudioOutput)
    }

    func testRevokeIsAtomicTerminalAndRejectsResurrection() {
        let fixture = CollaboratorFixture()
        let session = IRFFDecoderCollaboratorSession(
            configuration: fixture.configuration
        )
        let frame = IRFFVideoFrame()

        XCTAssertTrue(session.deliverVideoFrame(frame))
        var callbackObservedRevokedState = false
        XCTAssertTrue(
            session.revoke {
                callbackObservedRevokedState =
                    session.diagnostics.phase == .revoked &&
                    session.snapshot.delegate == nil &&
                    session.snapshot.source == nil &&
                    session.snapshot.videoOutput == nil &&
                    session.snapshot.audioOutput == nil
            }
        )
        XCTAssertTrue(callbackObservedRevokedState)
        XCTAssertFalse(session.revoke())
        XCTAssertFalse(session.updateDelegate(fixture.delegate))
        XCTAssertFalse(session.updateSource(fixture.source))
        XCTAssertFalse(
            session.updateVideoOutput(fixture.videoOutput)
        )
        XCTAssertFalse(
            session.updateAudioOutput(fixture.audioOutput)
        )
        XCTAssertFalse(session.install(fixture.configuration))
        XCTAssertFalse(session.deliverVideoFrame(frame))

        XCTAssertEqual(
            session.diagnostics,
            .init(
                phase: .revoked,
                generation: 2,
                hasDelegate: false,
                hasSource: false,
                hasVideoOutput: false,
                hasAudioOutput: false,
                installCount: 1,
                revokeCount: 1,
                acceptedVideoDeliveryCount: 1,
                rejectedVideoDeliveryCount: 1,
                rejectedUpdateCount: 5
            )
        )
    }

    func testConcurrentReadsInstallsUpdatesDeliveryAndRevokeRemainCoherent() {
        let first = CollaboratorFixture()
        let second = CollaboratorFixture()
        let session = IRFFDecoderCollaboratorSession(
            configuration: first.configuration
        )
        let frame = IRFFVideoFrame()

        DispatchQueue.concurrentPerform(iterations: 800) { index in
            if index == 400 {
                _ = session.revoke()
            }
            switch index % 8 {
            case 0:
                _ = session.snapshot
            case 1:
                _ = session.install(second.configuration)
            case 2:
                _ = session.updateDelegate(first.delegate)
            case 3:
                _ = session.updateSource(first.source)
            case 4:
                _ = session.updateVideoOutput(first.videoOutput)
            case 5:
                _ = session.updateAudioOutput(first.audioOutput)
            case 6:
                _ = session.deliverVideoFrame(frame)
            default:
                _ = session.withAudioOutput(default: 0) {
                    $0.samplingRate
                }
            }
        }
        _ = session.revoke()

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .revoked)
        XCTAssertFalse(diagnostics.hasDelegate)
        XCTAssertFalse(diagnostics.hasSource)
        XCTAssertFalse(diagnostics.hasVideoOutput)
        XCTAssertFalse(diagnostics.hasAudioOutput)
        XCTAssertEqual(diagnostics.revokeCount, 1)
        XCTAssertGreaterThan(
            diagnostics.acceptedVideoDeliveryCount +
                diagnostics.rejectedVideoDeliveryCount,
            0
        )
        XCTAssertGreaterThan(diagnostics.rejectedUpdateCount, 0)
    }

    func testRevokeWaitsForAdmittedVideoDeliveryAndRejectsLaterFrames() {
        let output = BlockingCollaboratorVideoOutput()
        let session = IRFFDecoderCollaboratorSession(
            configuration: .init(
                delegate: nil,
                source: nil,
                videoOutput: output,
                audioOutput: nil
            )
        )
        let deliveryFinished = DispatchSemaphore(value: 0)
        let revokeStarted = DispatchSemaphore(value: 0)
        let revokeFinished = DispatchSemaphore(value: 0)
        let deliveryResult = CollaboratorBoolBox()
        let revokeResult = CollaboratorBoolBox()

        DispatchQueue.global().async {
            deliveryResult.value = session.deliverVideoFrame(
                IRFFVideoFrame()
            )
            deliveryFinished.signal()
        }
        XCTAssertEqual(
            output.entered.wait(timeout: .now() + 2),
            .success
        )

        DispatchQueue.global().async {
            revokeStarted.signal()
            revokeResult.value = session.revoke()
            revokeFinished.signal()
        }
        XCTAssertEqual(
            revokeStarted.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(
            revokeFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )

        output.release.signal()
        XCTAssertEqual(
            deliveryFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(
            revokeFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertTrue(deliveryResult.value)
        XCTAssertTrue(revokeResult.value)
        XCTAssertFalse(
            session.deliverVideoFrame(IRFFVideoFrame())
        )
        XCTAssertEqual(output.receivedCount, 1)
    }

    func testVideoOutputMayReentrantlyRevokeWithoutDeadlock() {
        let output = ReentrantCollaboratorVideoOutput()
        var session: IRFFDecoderCollaboratorSession!
        session = IRFFDecoderCollaboratorSession(
            configuration: .init(
                delegate: nil,
                source: nil,
                videoOutput: output,
                audioOutput: nil
            )
        )
        output.onSend = {
            XCTAssertTrue(session.revoke())
        }

        XCTAssertTrue(
            session.deliverVideoFrame(IRFFVideoFrame())
        )
        XCTAssertEqual(session.diagnostics.phase, .revoked)
        XCTAssertFalse(
            session.deliverVideoFrame(IRFFVideoFrame())
        )
        XCTAssertEqual(output.receivedCount, 1)
    }

    func testDelegateCallbackUsesSnapshotOutsideLockAndMayRevoke() {
        let delegate = CollaboratorDelegateProbe()
        let session = IRFFDecoderCollaboratorSession(
            configuration: .init(
                delegate: delegate,
                source: nil,
                videoOutput: nil,
                audioOutput: nil
            )
        )

        let result = session.withDelegate(default: false) {
            XCTAssertTrue($0 === delegate)
            XCTAssertTrue(session.revoke())
            return true
        }

        XCTAssertTrue(result)
        XCTAssertEqual(session.diagnostics.phase, .revoked)
        XCTAssertFalse(
            session.withDelegate(default: false) { _ in true }
        )
    }

    func testAudioReadUsesSnapshotWithoutBlockingRevocation() {
        let audioOutput = CollaboratorAudioOutputProbe()
        let session = IRFFDecoderCollaboratorSession(
            configuration: .init(
                delegate: nil,
                source: nil,
                videoOutput: nil,
                audioOutput: audioOutput
            )
        )
        let readEntered = DispatchSemaphore(value: 0)
        let releaseRead = DispatchSemaphore(value: 0)
        let readFinished = DispatchSemaphore(value: 0)
        let revokeFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = session.withAudioOutput(
                default: UInt32(0)
            ) { output in
                readEntered.signal()
                _ = releaseRead.wait(timeout: .now() + 2)
                return output.numberOfChannels
            }
            readFinished.signal()
        }
        XCTAssertEqual(
            readEntered.wait(timeout: .now() + 2),
            .success
        )

        DispatchQueue.global().async {
            _ = session.revoke()
            revokeFinished.signal()
        }

        let revokeResult = revokeFinished.wait(
            timeout: .now() + 0.1
        )
        releaseRead.signal()
        XCTAssertEqual(
            readFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(revokeResult, .success)
        XCTAssertEqual(session.diagnostics.phase, .revoked)
    }
}

private final class CollaboratorFixture {
    let delegate = CollaboratorDelegateProbe()
    let source = CollaboratorDataSourceProbe()
    let videoOutput = ReentrantCollaboratorVideoOutput()
    let audioOutput = CollaboratorAudioOutputProbe()

    var configuration:
        IRFFDecoderCollaboratorSession.Configuration {
        .init(
            delegate: delegate,
            source: source,
            videoOutput: videoOutput,
            audioOutput: audioOutput
        )
    }
}

private final class CollaboratorDelegateProbe: IRFFDecoderDelegate {
    func decoderWillOpenInputStream(_ decoder: IRFFDecoder) {}
    func decoderDidPrepareToDecodeFrames(_ decoder: IRFFDecoder) {}
    func decoderDidEndOfFile(_ decoder: IRFFDecoder) {}
    func decoderDidPlaybackFinished(_ decoder: IRFFDecoder) {}
    func decoder(_ decoder: IRFFDecoder, didError error: Error) {}

    func decoder(
        _ decoder: IRFFDecoder,
        didChangeValueOfBuffering buffering: Bool
    ) {}

    func decoder(
        _ decoder: IRFFDecoder,
        didChangeValueOfBufferedDuration bufferedDuration: TimeInterval
    ) {}

    func decoder(
        _ decoder: IRFFDecoder,
        didChangeValueOfProgress progress: TimeInterval
    ) {}
}

private final class CollaboratorDataSourceProbe:
    IRFFVideoDecoderDataSource
{
    func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet: IRFFCompressedVideoPacket
    ) -> Bool {
        false
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet: IRFFCompressedVideoPacket
    ) -> IRFFVideoFrame? {
        nil
    }
}

private final class CollaboratorAudioOutputProbe:
    IRFFDecoderAudioOutput
{
    let numberOfChannels: UInt32 = 2
    let samplingRate: Float64 = 48_000
}

private final class ReentrantCollaboratorVideoOutput:
    NSObject,
    IRFFDecoderVideoOutput
{
    private let lock = NSLock()
    private var storedReceivedCount = 0
    var onSend: (() -> Void)?

    var receivedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReceivedCount
    }

    func send(videoFrame frame: IRFFVideoFrame) {
        lock.lock()
        storedReceivedCount += 1
        let onSend = onSend
        lock.unlock()
        onSend?()
    }
}

private final class BlockingCollaboratorVideoOutput:
    NSObject,
    IRFFDecoderVideoOutput
{
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedReceivedCount = 0

    var receivedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReceivedCount
    }

    func send(videoFrame frame: IRFFVideoFrame) {
        lock.lock()
        storedReceivedCount += 1
        lock.unlock()
        entered.signal()
        _ = release.wait(timeout: .now() + 2)
    }
}

private final class CollaboratorBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

private final class CollaboratorWeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}
