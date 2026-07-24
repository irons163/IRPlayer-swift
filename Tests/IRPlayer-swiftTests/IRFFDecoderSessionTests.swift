import IRFFMpeg
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDecoderSessionTests: XCTestCase {
    func testStartSchedulesOpenExactlyOnceAndRejectsDuplicateStart() {
        let queue = OperationQueue()
        queue.isSuspended = true
        let session = IRFFDecoderSession(operationQueue: queue)

        XCTAssertTrue(session.start {})
        XCTAssertFalse(session.start {})

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .opening)
        XCTAssertEqual(diagnostics.openScheduleCount, 1)
        XCTAssertTrue(diagnostics.hasOpenOperation)
        XCTAssertEqual(queue.operationCount, 1)

        queue.isSuspended = false
        queue.waitUntilAllOperationsAreFinished()
        XCTAssertTrue(session.close())
    }

    func testWorkersDependOnOpenAndRescheduleOnlyAfterFinishing() {
        let queue = OperationQueue()
        queue.isSuspended = true
        let session = IRFFDecoderSession(operationQueue: queue)

        XCTAssertTrue(session.start {})
        XCTAssertTrue(
            session.scheduleWorkers(
                includeVideo: true,
                read: {},
                decode: {},
                display: {}
            )
        )
        XCTAssertFalse(
            session.scheduleWorkers(
                includeVideo: true,
                read: {},
                decode: {},
                display: {}
            )
        )

        let pendingOperations = queue.operations
        let openOperation = try? XCTUnwrap(
            pendingOperations.first { $0.dependencies.isEmpty }
        )
        XCTAssertNotNil(openOperation)
        XCTAssertEqual(pendingOperations.count, 4)
        XCTAssertEqual(
            pendingOperations.first {
                $0.name == "IRFFDecoderSession.open"
            }?.qualityOfService,
            .userInitiated
        )
        XCTAssertEqual(
            pendingOperations.first {
                $0.name == "IRFFDecoderSession.read"
            }?.qualityOfService,
            .userInitiated
        )
        XCTAssertEqual(
            pendingOperations.first {
                $0.name == "IRFFDecoderSession.decode"
            }?.qualityOfService,
            .default
        )
        XCTAssertEqual(
            pendingOperations.first {
                $0.name == "IRFFDecoderSession.display"
            }?.qualityOfService,
            .default
        )
        XCTAssertTrue(
            pendingOperations
                .filter { $0 !== openOperation }
                .allSatisfy { operation in
                    operation.dependencies.contains { $0 === openOperation }
                }
        )

        queue.isSuspended = false
        queue.waitUntilAllOperationsAreFinished()

        XCTAssertTrue(
            session.scheduleWorkers(
                includeVideo: true,
                read: {},
                decode: {},
                display: {}
            )
        )
        queue.waitUntilAllOperationsAreFinished()

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .active)
        XCTAssertEqual(diagnostics.readScheduleCount, 2)
        XCTAssertEqual(diagnostics.decodeScheduleCount, 2)
        XCTAssertEqual(diagnostics.displayScheduleCount, 2)
        XCTAssertTrue(session.close())
    }

    func testAudioOnlySessionSchedulesReadWithoutVideoWorkers() {
        let queue = OperationQueue()
        queue.isSuspended = true
        let session = IRFFDecoderSession(operationQueue: queue)

        XCTAssertFalse(
            session.scheduleWorkers(
                includeVideo: false,
                read: {},
                decode: {},
                display: {}
            )
        )
        XCTAssertTrue(session.start {})
        XCTAssertTrue(
            session.scheduleWorkers(
                includeVideo: false,
                read: {},
                decode: {},
                display: {}
            )
        )

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.readScheduleCount, 1)
        XCTAssertEqual(diagnostics.decodeScheduleCount, 0)
        XCTAssertEqual(diagnostics.displayScheduleCount, 0)

        queue.isSuspended = false
        queue.waitUntilAllOperationsAreFinished()
        XCTAssertTrue(session.close())
    }

    func testFailedOpenRejectsWorkersAndRetainsResourcesUntilClose() {
        let queue = OperationQueue()
        queue.isSuspended = true
        let session = IRFFDecoderSession(operationQueue: queue)
        let formatContext = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/session-failure.mp4"),
            videoFormat: .mpeg4
        )

        XCTAssertTrue(session.start {})
        XCTAssertTrue(session.installFormatContext(formatContext))
        XCTAssertTrue(session.markOpenFailed())
        XCTAssertFalse(
            session.scheduleWorkers(
                includeVideo: false,
                read: {},
                decode: {},
                display: {}
            )
        )
        XCTAssertEqual(session.diagnostics.phase, .failed)
        XCTAssertTrue(session.diagnostics.hasFormatContext)
        XCTAssertTrue(
            session.withResources(default: false) {
                $0.formatContext === formatContext
            }
        )

        queue.isSuspended = false
        queue.waitUntilAllOperationsAreFinished()
        XCTAssertTrue(session.close())
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.diagnostics.hasFormatContext)
    }

    func testCloseWaitsForRunningOperationAndRejectsNewScheduling() {
        let queue = OperationQueue()
        let session = IRFFDecoderSession(operationQueue: queue)
        let operationStarted = DispatchSemaphore(value: 0)
        let releaseOperation = DispatchSemaphore(value: 0)
        let closeFinished = expectation(description: "close finished")

        XCTAssertTrue(
            session.start {
                operationStarted.signal()
                releaseOperation.wait()
            }
        )
        XCTAssertEqual(operationStarted.wait(timeout: .now() + 2), .success)

        DispatchQueue.global().async {
            XCTAssertTrue(session.close())
            closeFinished.fulfill()
        }

        XCTAssertTrue(waitUntil { session.diagnostics.phase == .closing })
        XCTAssertFalse(
            session.scheduleWorkers(
                includeVideo: false,
                read: {},
                decode: {},
                display: {}
            )
        )
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(session.diagnostics.phase, .closing)

        DispatchQueue.global(qos: .userInitiated).async {
            releaseOperation.signal()
        }
        wait(for: [closeFinished], timeout: 2)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.diagnostics.hasOperationQueue)
    }

    func testCloseWaitsForExternalResourceLeaseBeforeDestroyingResources() {
        let queue = OperationQueue()
        let session = IRFFDecoderSession(operationQueue: queue)
        let formatContext = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/session-lease.mp4"),
            videoFormat: .mpeg4
        )
        let leaseStarted = DispatchSemaphore(value: 0)
        let releaseLease = DispatchSemaphore(value: 0)
        let leaseFinished = expectation(description: "lease finished")
        let closeFinished = expectation(description: "close finished")

        XCTAssertTrue(session.start {})
        queue.waitUntilAllOperationsAreFinished()
        XCTAssertTrue(session.installFormatContext(formatContext))
        XCTAssertTrue(session.markOpenSucceeded())

        DispatchQueue.global().async {
            session.withResources(default: ()) { resources in
                XCTAssertTrue(resources.formatContext === formatContext)
                leaseStarted.signal()
                releaseLease.wait()
            }
            leaseFinished.fulfill()
        }
        XCTAssertEqual(leaseStarted.wait(timeout: .now() + 2), .success)

        DispatchQueue.global().async {
            XCTAssertTrue(session.close())
            closeFinished.fulfill()
        }

        XCTAssertTrue(waitUntil { session.diagnostics.phase == .closing })
        XCTAssertEqual(session.diagnostics.externalLeaseCount, 1)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(session.diagnostics.phase, .closing)

        releaseLease.signal()
        wait(for: [leaseFinished, closeFinished], timeout: 2)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.diagnostics.hasFormatContext)
        XCTAssertEqual(
            session.withResources(default: false) { _ in true },
            false
        )
    }

    func testConcurrentCloseElectsOneOwnerAndDrainsSession() {
        let session = IRFFDecoderSession()
        let resultLock = NSLock()
        var closeOwnerCount = 0

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard session.close() else { return }
            resultLock.lock()
            closeOwnerCount += 1
            resultLock.unlock()
        }

        XCTAssertEqual(closeOwnerCount, 1)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.diagnostics.hasOperationQueue)
        XCTAssertFalse(session.close())
    }

    func testClosedSessionRejectsOpenAndResourceInstallation() {
        let session = IRFFDecoderSession()
        let formatContext = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/session-closed.mp4"),
            videoFormat: .mpeg4
        )

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.start {})
        XCTAssertFalse(session.installFormatContext(formatContext))
        XCTAssertFalse(session.markOpenFailed())
    }

    func testOpeningSessionDoesNotExposePartiallyInstalledResources() {
        let queue = OperationQueue()
        let session = IRFFDecoderSession(operationQueue: queue)
        let formatContext = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/session-opening.mp4"),
            videoFormat: .mpeg4
        )

        XCTAssertTrue(session.start {})
        queue.waitUntilAllOperationsAreFinished()
        XCTAssertTrue(session.installFormatContext(formatContext))
        XCTAssertFalse(
            session.withResources(default: false) {
                $0.formatContext === formatContext
            }
        )

        XCTAssertTrue(session.markOpenSucceeded())
        XCTAssertTrue(
            session.withResources(default: false) {
                $0.formatContext === formatContext
            }
        )
        XCTAssertTrue(session.close())
    }

    func testFormatInstallationRacingCloseIsRejectedOrDrained() {
        for iteration in 0..<100 {
            let queue = OperationQueue()
            let session = IRFFDecoderSession(operationQueue: queue)
            let formatContext = IRFFFormatContext(
                contentURL: URL(
                    fileURLWithPath: "/tmp/session-race-\(iteration).mp4"
                ),
                videoFormat: .mpeg4
            )
            let workers = DispatchGroup()
            let resultLock = NSLock()
            var accepted = false

            XCTAssertTrue(session.start {})
            queue.waitUntilAllOperationsAreFinished()

            workers.enter()
            DispatchQueue.global().async {
                let result = session.installFormatContext(formatContext)
                resultLock.lock()
                accepted = result
                resultLock.unlock()
                workers.leave()
            }
            workers.enter()
            DispatchQueue.global().async {
                _ = session.close()
                workers.leave()
            }

            XCTAssertEqual(workers.wait(timeout: .now() + 2), .success)
            resultLock.lock()
            let installationWasAccepted = accepted
            resultLock.unlock()
            if !installationWasAccepted {
                formatContext.destroy()
            }

            XCTAssertEqual(session.diagnostics.phase, .closed)
            XCTAssertFalse(session.diagnostics.hasFormatContext)
        }
    }

    func testVideoSourceUpdatesReachInstalledDecoderDuringOpening()
    {
        let queue = OperationQueue()
        let session = IRFFDecoderSession(
            operationQueue: queue
        )
        let sources = (0..<8).map { _ in IRFFVideoInput() }
        var codecContext = AVCodecContext()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            XCTAssertTrue(session.start {})
            queue.waitUntilAllOperationsAreFinished()
            XCTAssertTrue(
                session.installVideoDecoder(decoder)
            )

            DispatchQueue.concurrentPerform(iterations: 1_000) {
                index in
                if index.isMultiple(of: 2) {
                    session.updateVideoDecoderSource(
                        sources[index % sources.count]
                    )
                } else {
                    _ = decoder.source
                }
            }

            session.updateVideoDecoderSource(sources[0])
            XCTAssertTrue(decoder.source === sources[0])
            session.updateVideoDecoderSource(nil)
            XCTAssertNil(decoder.source)
            XCTAssertTrue(session.close())
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return condition()
    }
}
