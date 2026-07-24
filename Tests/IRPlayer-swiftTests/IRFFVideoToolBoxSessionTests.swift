import CoreVideo
import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFVideoToolBoxSessionTests: XCTestCase {
    func testCompleteGenerationPublishesAtomicallyAndDrainsExactlyOnce() {
        let session = IRFFVideoToolBoxSession<String>()

        XCTAssertEqual(session.diagnostics.phase, .idle)
        let ticket = session.beginSetup()
        XCTAssertNotNil(ticket)
        XCTAssertEqual(session.diagnostics.phase, .settingUp)
        XCTAssertNil(session.beginSetup())

        XCTAssertTrue(session.install("generation", for: ticket!))
        XCTAssertEqual(session.diagnostics.phase, .active)
        XCTAssertEqual(
            session.withResource(default: "missing") { $0 },
            "generation"
        )

        var drainedResources: [String] = []
        XCTAssertTrue(
            session.reset { drainedResources.append($0) }
        )
        XCTAssertEqual(drainedResources, ["generation"])
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertTrue(
            session.reset { drainedResources.append($0) }
        )
        XCTAssertEqual(drainedResources, ["generation"])
    }

    func testResetInvalidatesInFlightSetupTicket() {
        let session = IRFFVideoToolBoxSession<Int>()
        let ticket = session.beginSetup()

        XCTAssertTrue(session.reset { _ in XCTFail("No resource") })

        XCTAssertFalse(session.install(42, for: ticket!))
        XCTAssertEqual(
            session.withResource(default: -1) { $0 },
            -1
        )
        XCTAssertEqual(session.diagnostics.phase, .idle)
    }

    func testCancelSetupReturnsToIdleAndRejectsTicket() {
        let session = IRFFVideoToolBoxSession<Int>()
        let ticket = try! XCTUnwrap(session.beginSetup())

        session.cancelSetup(ticket)

        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertFalse(session.install(42, for: ticket))
        let nextTicket = try! XCTUnwrap(session.beginSetup())
        session.cancelSetup(nextTicket)
        XCTAssertEqual(session.diagnostics.phase, .idle)
    }

    func testCloseInvalidatesSetupAndIsTerminal() {
        let session = IRFFVideoToolBoxSession<Int>()
        let ticket = session.beginSetup()

        XCTAssertTrue(session.close { _ in XCTFail("No resource") })

        XCTAssertFalse(session.install(42, for: ticket!))
        XCTAssertNil(session.beginSetup())
        XCTAssertFalse(session.reset { _ in XCTFail("No resource") })
        XCTAssertFalse(session.close { _ in XCTFail("No resource") })
        XCTAssertEqual(session.diagnostics.phase, .closed)
    }

    func testResetWaitsForActiveResourceLease() {
        let session = IRFFVideoToolBoxSession<String>()
        let ticket = try! XCTUnwrap(session.beginSetup())
        XCTAssertTrue(session.install("generation", for: ticket))

        let leaseEntered = expectation(description: "lease entered")
        let releaseLease = DispatchSemaphore(value: 0)
        let leaseFinished = expectation(description: "lease finished")
        DispatchQueue.global().async {
            session.withResource(default: ()) { _ in
                leaseEntered.fulfill()
                releaseLease.wait()
            }
            leaseFinished.fulfill()
        }
        wait(for: [leaseEntered], timeout: 1)

        let drainFinished = DispatchSemaphore(value: 0)
        let drainedResource = LockedVideoToolBoxTestValue<String?>(nil)
        DispatchQueue.global().async {
            session.reset {
                drainedResource.value = $0
            }
            drainFinished.signal()
        }

        XCTAssertEqual(
            drainFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )
        XCTAssertEqual(session.diagnostics.phase, .resetting)

        releaseLease.signal()
        wait(for: [leaseFinished], timeout: 1)
        XCTAssertEqual(
            drainFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(drainedResource.value, "generation")

        XCTAssertEqual(session.diagnostics.phase, .idle)
    }

    func testConcurrentCloseElectsOneDrainOwner() {
        let session = IRFFVideoToolBoxSession<Int>()
        let ticket = try! XCTUnwrap(session.beginSetup())
        XCTAssertTrue(session.install(7, for: ticket))
        let drains = LockedVideoToolBoxTestValue<[Int]>([])

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            session.close { resource in
                drains.withValue { $0.append(resource) }
            }
        }

        XCTAssertEqual(drains.value.count, 1)
        XCTAssertEqual(drains.value.first, 7)
        XCTAssertEqual(session.diagnostics.phase, .closed)
    }

    func testCloseWaitsForResetTeardownToFinish() {
        let session = IRFFVideoToolBoxSession<Int>()
        let ticket = try! XCTUnwrap(session.beginSetup())
        XCTAssertTrue(session.install(7, for: ticket))

        let resetEntered = DispatchSemaphore(value: 0)
        let releaseReset = DispatchSemaphore(value: 0)
        let resetFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            session.reset { _ in
                resetEntered.signal()
                releaseReset.wait()
            }
            resetFinished.signal()
        }
        XCTAssertEqual(
            resetEntered.wait(timeout: .now() + 1),
            .success
        )

        let closeFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            session.close { _ in XCTFail("Reset already drained resource") }
            closeFinished.signal()
        }
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )

        releaseReset.signal()
        XCTAssertEqual(
            resetFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(session.diagnostics.phase, .closed)
    }

    func testCallbackStatePublishesCoherentResultAndReset() throws {
        let state = IRFFVideoToolBoxCallbackState()
        XCTAssertEqual(state.snapshot.status, noErr)
        XCTAssertNil(state.snapshot.imageBuffer)

        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                nil,
                4,
                4,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            ),
            kCVReturnSuccess
        )
        let imageBuffer = try XCTUnwrap(pixelBuffer)

        state.publish(status: -7, imageBuffer: imageBuffer)
        let published = state.snapshot
        XCTAssertEqual(published.status, -7)
        XCTAssertTrue(published.imageBuffer === imageBuffer)

        state.reset()
        XCTAssertEqual(state.snapshot.status, noErr)
        XCTAssertNil(state.snapshot.imageBuffer)
    }

    func testCallbackStateSupportsConcurrentPublishResetAndSnapshots() {
        let state = IRFFVideoToolBoxCallbackState()
        let invalidSnapshots = LockedVideoToolBoxTestValue(0)

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            switch index % 3 {
            case 0:
                state.reset()
            case 1:
                state.publish(status: OSStatus(index), imageBuffer: nil)
            default:
                let snapshot = state.snapshot
                if snapshot.status == noErr && snapshot.imageBuffer != nil {
                    invalidSnapshots.withValue { $0 += 1 }
                }
            }
        }

        XCTAssertEqual(invalidSnapshots.value, 0)
    }
}

private final class LockedVideoToolBoxTestValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
