import Foundation
import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFFormatContextResourcesTests: XCTestCase {
    func testGenerationConcurrentCloseTearsDownEveryResourceExactlyOnce() {
        let events = LockedFormatContextTestValue<[String]>([])
        let runtime = makeRuntime(events: events)
        let generation = IRFFFormatContextGeneration(
            formatContext: pointer(0x1000),
            callbackReference: UnsafeMutableRawPointer(bitPattern: 0x4000)!,
            runtime: runtime
        )
        generation.installVideoCodecContext(pointer(0x2000))
        generation.installAudioCodecContext(pointer(0x3000))
        let closeOwners = LockedFormatContextTestValue(0)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if generation.close() {
                closeOwners.withValue { $0 += 1 }
            }
        }

        XCTAssertEqual(closeOwners.value, 1)
        XCTAssertEqual(
            events.value,
            [
                "free-codec-0x2000",
                "free-codec-0x3000",
                "close-input-0x1000",
                "release-callback-0x4000"
            ]
        )
        XCTAssertEqual(
            generation.diagnostics,
            .init(
                isClosed: true,
                hasFormatContext: false,
                hasVideoCodecContext: false,
                hasAudioCodecContext: false,
                hasCallbackReference: false
            )
        )
    }

    func testReplacingAndDestroyingAudioContextFreeEachAllocationOnce() {
        let events = LockedFormatContextTestValue<[String]>([])
        let generation = IRFFFormatContextGeneration(
            formatContext: pointer(0x1000),
            callbackReference: UnsafeMutableRawPointer(bitPattern: 0x4000)!,
            runtime: makeRuntime(events: events)
        )
        generation.installAudioCodecContext(pointer(0x2000))

        generation.replaceAudioCodecContext(with: pointer(0x3000))
        generation.destroyAudioTrack()
        generation.close()

        XCTAssertEqual(
            events.value,
            [
                "free-codec-0x2000",
                "free-codec-0x3000",
                "close-input-0x1000",
                "release-callback-0x4000"
            ]
        )
    }

    func testConcurrentCloseWaitsForResourceTeardownToFinish() {
        let teardownEntered = DispatchSemaphore(value: 0)
        let releaseTeardown = DispatchSemaphore(value: 0)
        let firstCloseFinished = DispatchSemaphore(value: 0)
        let secondCloseFinished = DispatchSemaphore(value: 0)
        let runtime = IRFFFormatContextResourceRuntime(
            freeCodecContext: { context in
                if context != nil {
                    teardownEntered.signal()
                    releaseTeardown.wait()
                }
                context = nil
            },
            closeInputContext: { $0 = nil },
            releaseCallbackReference: { _ in }
        )
        let generation = IRFFFormatContextGeneration(
            formatContext: pointer(0x1000),
            callbackReference:
                UnsafeMutableRawPointer(bitPattern: 0x3000)!,
            runtime: runtime
        )
        generation.installVideoCodecContext(pointer(0x2000))

        DispatchQueue.global().async {
            generation.close()
            firstCloseFinished.signal()
        }
        XCTAssertEqual(
            teardownEntered.wait(timeout: .now() + 1),
            .success
        )
        DispatchQueue.global().async {
            generation.close()
            secondCloseFinished.signal()
        }
        XCTAssertEqual(
            secondCloseFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )

        releaseTeardown.signal()
        XCTAssertEqual(
            firstCloseFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            secondCloseFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertTrue(generation.diagnostics.isClosed)
    }

    func testInterruptStateUsesDelegateAndForcedCloseDecision() {
        let context = makeContext()
        let delegate = FormatContextInterruptDelegate(
            shouldInterrupt: false
        )
        let state = IRFFFormatContextInterruptState()
        state.bind(context: context)
        state.setDelegate(delegate)
        let reference = state.makeRetainedCallbackReference()
        defer {
            IRFFFormatContextInterruptState
                .releaseRetainedCallbackReference(reference)
        }

        XCTAssertEqual(
            ffmpeg_interrupt_callback(ctx: reference),
            0
        )
        delegate.shouldInterrupt = true
        XCTAssertEqual(
            ffmpeg_interrupt_callback(ctx: reference),
            1
        )
        delegate.shouldInterrupt = false
        state.requestClose()
        XCTAssertEqual(
            ffmpeg_interrupt_callback(ctx: reference),
            1
        )
        XCTAssertTrue(state.diagnostics.closeRequested)
    }

    func testInterruptStateSafelyInterruptsAfterFacadeIsReleased() {
        let state = IRFFFormatContextInterruptState()
        var context: IRFFFormatContext? = makeContext()
        state.bind(context: context!)
        XCTAssertFalse(state.shouldInterrupt())

        context = nil

        XCTAssertTrue(state.shouldInterrupt())
        XCTAssertFalse(state.diagnostics.hasContext)
    }

    func testInterruptStateSupportsConcurrentReadsAndUpdates() {
        let context = makeContext()
        let delegate = FormatContextInterruptDelegate(
            shouldInterrupt: false
        )
        let state = IRFFFormatContextInterruptState()
        state.bind(context: context)

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            switch index % 4 {
            case 0:
                state.setDelegate(delegate)
            case 1:
                state.setDelegate(nil)
            case 2:
                _ = state.shouldInterrupt()
            default:
                _ = state.diagnostics
            }
        }

        state.requestClose()
        XCTAssertTrue(state.shouldInterrupt())
    }

    private func makeContext() -> IRFFFormatContext {
        IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"),
            videoFormat: .mpeg4
        )
    }

    private func makeRuntime(
        events: LockedFormatContextTestValue<[String]>
    ) -> IRFFFormatContextResourceRuntime {
        IRFFFormatContextResourceRuntime(
            freeCodecContext: { context in
                if let context {
                    events.withValue {
                        $0.append(
                            "free-codec-\(Self.address(context))"
                        )
                    }
                }
                context = nil
            },
            closeInputContext: { context in
                if let context {
                    events.withValue {
                        $0.append(
                            "close-input-\(Self.address(context))"
                        )
                    }
                }
                context = nil
            },
            releaseCallbackReference: { reference in
                events.withValue {
                    $0.append(
                        "release-callback-\(Self.address(reference))"
                    )
                }
            }
        )
    }

    private func pointer<T>(_ address: Int)
        -> UnsafeMutablePointer<T>
    {
        UnsafeMutablePointer<T>(bitPattern: address)!
    }

    private static func address<T>(
        _ pointer: UnsafeMutablePointer<T>
    ) -> String {
        address(UnsafeMutableRawPointer(pointer))
    }

    private static func address(
        _ pointer: UnsafeMutableRawPointer
    ) -> String {
        "0x" + String(UInt(bitPattern: pointer), radix: 16)
    }
}

private final class LockedFormatContextTestValue<Value>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
