//
//  IRPlayerLoggerTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/7/24.
//

import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlayerLoggerTests: XCTestCase {
    func testEverySeverityUsesOneDelegateSnapshot() {
        let session = IRPlayerLoggingSession(
            subsystem: "IRPlayerTests"
        )
        let recorder = LoggingRecorder()
        session.delegate = recorder
        let logger = IRPlayerLogger(
            subsystem: "IRPlayerTests",
            category: "unit",
            session: session
        )

        logger.debug("debug")
        logger.info("info")
        logger.warning("warning")
        logger.error("error")

        XCTAssertEqual(
            recorder.records,
            [
                .init(
                    message: "debug",
                    level: .debug,
                    category: "unit"
                ),
                .init(
                    message: "info",
                    level: .info,
                    category: "unit"
                ),
                .init(
                    message: "warning",
                    level: .warning,
                    category: "unit"
                ),
                .init(
                    message: "error",
                    level: .error,
                    category: "unit"
                )
            ]
        )
        XCTAssertEqual(session.diagnostics.emissionCount, 4)
        XCTAssertEqual(
            session.diagnostics.completedDeliveryCount,
            4
        )
        XCTAssertEqual(
            session.diagnostics.delegateDeliveryCount,
            4
        )
        XCTAssertEqual(
            session.diagnostics.fallbackDeliveryCount,
            0
        )
    }

    func testDelegateIsWeakAndMissingDelegateUsesFallback() {
        let session = IRPlayerLoggingSession(
            subsystem: "IRPlayerTests"
        )
        weak var weakRecorder: LoggingRecorder?

        autoreleasepool {
            let recorder = LoggingRecorder()
            weakRecorder = recorder
            session.delegate = recorder
            XCTAssertTrue(session.diagnostics.hasDelegate)
        }

        XCTAssertNil(weakRecorder)
        XCTAssertFalse(session.diagnostics.hasDelegate)

        var fallbackMessages: [String] = []
        XCTAssertTrue(
            session.emit(
                "fallback",
                level: .warning,
                category: "unit"
            ) {
                fallbackMessages.append("fallback")
            }
        )

        XCTAssertEqual(fallbackMessages, ["fallback"])
        XCTAssertEqual(
            session.diagnostics.fallbackDeliveryCount,
            1
        )
    }

    func testDelegateMayReplaceItselfAndLogReentrantly() {
        let session = IRPlayerLoggingSession(
            subsystem: "IRPlayerTests"
        )
        var fallbackMessages: [String] = []
        let recorder = LoggingRecorder { record in
            guard record.message == "outer" else { return }
            session.delegate = nil
            _ = session.emit(
                "inner",
                level: .info,
                category: "nested"
            ) {
                fallbackMessages.append("inner")
            }
        }
        session.delegate = recorder

        XCTAssertTrue(
            session.emit(
                "outer",
                level: .debug,
                category: "unit"
            ) {
                XCTFail("Outer emission should use its delegate")
            }
        )

        XCTAssertEqual(recorder.records.map(\.message), ["outer"])
        XCTAssertEqual(fallbackMessages, ["inner"])
        XCTAssertNil(session.delegate)
        XCTAssertEqual(session.diagnostics.emissionCount, 2)
        XCTAssertEqual(
            session.diagnostics.delegateDeliveryCount,
            1
        )
        XCTAssertEqual(
            session.diagnostics.fallbackDeliveryCount,
            1
        )
        XCTAssertEqual(
            session.diagnostics.activeDeliveryCount,
            0
        )
    }

    func testAdmittedDeliveryOwnsDelegateSnapshotAcrossClose() {
        let session = IRPlayerLoggingSession(
            subsystem: "IRPlayerTests"
        )
        let callbackEntered = expectation(
            description: "delegate callback entered"
        )
        let emissionCompleted = expectation(
            description: "emission completed"
        )
        let resumeCallback = DispatchSemaphore(value: 0)
        var recorder: LoggingRecorder? = LoggingRecorder {
            _ in
            callbackEntered.fulfill()
            resumeCallback.wait()
        }
        weak var weakRecorder: LoggingRecorder?
        weakRecorder = recorder
        session.delegate = recorder

        DispatchQueue.global().async {
            _ = session.emit(
                "admitted",
                level: .info,
                category: "unit"
            ) {
                XCTFail(
                    "Admitted delivery should keep its delegate snapshot"
                )
            }
            emissionCompleted.fulfill()
        }

        wait(for: [callbackEntered], timeout: 1)
        XCTAssertTrue(session.close())
        recorder = nil
        XCTAssertNotNil(weakRecorder)

        resumeCallback.signal()
        wait(for: [emissionCompleted], timeout: 1)

        XCTAssertNil(weakRecorder)
        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .closed)
        XCTAssertEqual(diagnostics.activeDeliveryCount, 0)
        XCTAssertEqual(diagnostics.emissionCount, 1)
        XCTAssertEqual(diagnostics.completedDeliveryCount, 1)
        XCTAssertEqual(diagnostics.delegateDeliveryCount, 1)
    }

    func testSubsystemReplacementPublishesMatchingDefaultLogger() {
        let session = IRPlayerLoggingSession(
            subsystem: "original"
        )

        XCTAssertTrue(
            session.replaceSubsystem("  replacement \n")
        )
        var diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.subsystem, "replacement")
        XCTAssertEqual(
            diagnostics.libraryLoggerSubsystem,
            "replacement"
        )
        XCTAssertEqual(
            diagnostics.libraryLoggerCategory,
            "library"
        )
        XCTAssertEqual(
            session.libraryLogger.configuration,
            .init(
                subsystem: "replacement",
                category: "library"
            )
        )

        XCTAssertTrue(session.replaceSubsystem(" \n "))
        diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.subsystem, "IRPlayerImp")
        XCTAssertEqual(
            diagnostics.libraryLoggerSubsystem,
            "IRPlayerImp"
        )
        XCTAssertEqual(diagnostics.configurationGeneration, 3)
    }

    func testExplicitLibraryLoggerIsReboundWithoutChangingSubsystem() {
        let session = IRPlayerLoggingSession(
            subsystem: "owner"
        )
        let recorder = LoggingRecorder()
        session.delegate = recorder
        let customLogger = IRPlayerLogger(
            subsystem: "custom",
            category: "render"
        )

        XCTAssertTrue(
            session.replaceLibraryLogger(customLogger)
        )
        let logger = session.libraryLogger
        logger.warning("custom message")

        XCTAssertEqual(session.subsystem, "owner")
        XCTAssertEqual(
            logger.configuration,
            .init(subsystem: "custom", category: "render")
        )
        XCTAssertEqual(
            recorder.records,
            [
                .init(
                    message: "custom message",
                    level: .warning,
                    category: "render"
                )
            ]
        )
    }

    func testCloseIsTerminalAndRejectsMutationAndEmission() {
        let session = IRPlayerLoggingSession(
            subsystem: "original"
        )
        let recorder = LoggingRecorder()
        session.delegate = recorder
        var fallbackCount = 0

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertFalse(
            session.replaceSubsystem("replacement")
        )
        XCTAssertFalse(
            session.replaceLibraryLogger(
                IRPlayerLogger(
                    subsystem: "custom",
                    category: "unit"
                )
            )
        )
        XCTAssertFalse(session.replaceDelegate(recorder))
        XCTAssertFalse(
            session.emit(
                "rejected",
                level: .error,
                category: "unit"
            ) {
                fallbackCount += 1
            }
        )

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .closed)
        XCTAssertFalse(diagnostics.hasDelegate)
        XCTAssertEqual(diagnostics.subsystem, "original")
        XCTAssertEqual(diagnostics.emissionCount, 0)
        XCTAssertEqual(diagnostics.rejectedEmissionCount, 1)
        XCTAssertEqual(diagnostics.rejectedMutationCount, 3)
        XCTAssertEqual(diagnostics.closeCount, 1)
        XCTAssertEqual(fallbackCount, 0)
        XCTAssertEqual(recorder.records, [])
    }

    func testLoggerDoesNotRetainOwningSession() {
        weak var weakSession: IRPlayerLoggingSession?
        var logger: IRPlayerLogger?

        autoreleasepool {
            let session = IRPlayerLoggingSession(
                subsystem: "temporary"
            )
            weakSession = session
            logger = IRPlayerLogger(
                subsystem: "temporary",
                category: "unit",
                session: session
            )
            session.libraryLogger = logger!
        }

        XCTAssertNil(weakSession)
        XCTAssertEqual(
            logger?.configuration,
            .init(subsystem: "temporary", category: "unit")
        )
        withExtendedLifetime(logger) {}
    }

    func testConcurrentConfigurationDelegateEmissionAndCloseAreCoherent() {
        let session = IRPlayerLoggingSession(
            subsystem: "initial"
        )
        let recorders = (0..<8).map { _ in
            LoggingRecorder()
        }
        let fallbackCounter = LockedIntCounter()

        for index in 0..<20 {
            _ = session.emit(
                "warmup-\(index)",
                level: .debug,
                category: "warmup"
            ) {
                fallbackCounter.increment()
            }
        }

        DispatchQueue.concurrentPerform(iterations: 2_000) {
            index in
            switch index % 6 {
            case 0:
                _ = session.replaceDelegate(
                    recorders[index % recorders.count]
                )
            case 1:
                _ = session.replaceSubsystem(
                    "subsystem-\(index)"
                )
            case 2:
                _ = session.replaceLibraryLogger(
                    IRPlayerLogger(
                        subsystem: "custom-\(index)",
                        category: "category-\(index)"
                    )
                )
            case 3:
                _ = session.emit(
                    "message-\(index)",
                    level: .info,
                    category: "concurrent"
                ) {
                    fallbackCounter.increment()
                }
            case 4:
                _ = session.diagnostics
            default:
                if index == 1_001 {
                    _ = session.close()
                } else {
                    _ = session.emit(
                        "message-\(index)",
                        level: .warning,
                        category: "concurrent"
                    ) {
                        fallbackCounter.increment()
                    }
                }
            }
        }
        _ = session.close()

        let diagnostics = session.diagnostics
        let delegateRecordCount = recorders.reduce(0) {
            $0 + $1.records.count
        }
        XCTAssertEqual(diagnostics.phase, .closed)
        XCTAssertEqual(diagnostics.activeDeliveryCount, 0)
        XCTAssertEqual(
            diagnostics.completedDeliveryCount,
            diagnostics.emissionCount
        )
        XCTAssertEqual(
            diagnostics.delegateDeliveryCount +
                diagnostics.fallbackDeliveryCount,
            diagnostics.emissionCount
        )
        XCTAssertEqual(
            delegateRecordCount + fallbackCounter.value,
            diagnostics.emissionCount
        )
        XCTAssertGreaterThanOrEqual(diagnostics.emissionCount, 20)
        XCTAssertEqual(diagnostics.closeCount, 1)
        XCTAssertFalse(diagnostics.hasDelegate)
    }
}

private struct LoggingRecord: Equatable {
    let message: String
    let level: IRPlayerLogLevel
    let category: String
}

private final class LoggingRecorder:
    IRPlayerLoggerDelegate,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedRecords: [LoggingRecord] = []
    private let onRecord: ((LoggingRecord) -> Void)?

    init(
        onRecord: ((LoggingRecord) -> Void)? = nil
    ) {
        self.onRecord = onRecord
    }

    var records: [LoggingRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storedRecords
    }

    func irPlayer(
        didLog message: String,
        level: IRPlayerLogLevel,
        category: String
    ) {
        let record = LoggingRecord(
            message: message,
            level: level,
            category: category
        )
        lock.lock()
        storedRecords.append(record)
        lock.unlock()
        onRecord?(record)
    }
}

private final class LockedIntCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
