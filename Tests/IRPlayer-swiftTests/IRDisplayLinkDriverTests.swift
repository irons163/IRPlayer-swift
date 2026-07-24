import UIKit
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRDisplayLinkDriverTests:
    XCTestCase
{
    func testDriverStartsUninstalled() {
        let driver =
            IRSystemDisplayLinkDriver()

        XCTAssertEqual(
            driver.snapshot,
            IRDisplayLinkSnapshot(
                phase: .uninstalled,
                scheduledMode: nil
            )
        )
    }

    func testInstallSchedulesPausedCommonModeLink() {
        let driver =
            IRSystemDisplayLinkDriver()
        defer { driver.close() }

        XCTAssertTrue(driver.install { _ in })
        XCTAssertEqual(driver.snapshot.phase, .idle)
        XCTAssertEqual(
            driver.snapshot.scheduledMode,
            RunLoop.Mode.common.rawValue
        )
    }

    func testDuplicateInstallIsRejected() {
        let driver =
            IRSystemDisplayLinkDriver()
        defer { driver.close() }

        XCTAssertTrue(driver.install { _ in })
        XCTAssertFalse(driver.install { _ in })
        XCTAssertEqual(driver.snapshot.phase, .idle)
    }

    func testActiveAndPausedPhasesControlDelivery() {
        let driver =
            IRSystemDisplayLinkDriver()
        var timestamps: [TimeInterval] = []
        defer { driver.close() }
        XCTAssertTrue(
            driver.install {
                timestamps.append($0)
            }
        )

        driver.emit(timestamp: 1)
        XCTAssertTrue(driver.setActive(true))
        driver.emit(timestamp: 2)
        XCTAssertTrue(driver.setActive(false))
        driver.emit(timestamp: 3)

        XCTAssertEqual(timestamps, [2])
        XCTAssertEqual(driver.snapshot.phase, .idle)
    }

    func testCloseIsTerminalAndRepeatable() {
        let driver =
            IRSystemDisplayLinkDriver()
        XCTAssertTrue(driver.install { _ in })

        XCTAssertTrue(driver.close())
        XCTAssertFalse(driver.close())
        XCTAssertFalse(driver.setActive(true))
        XCTAssertFalse(driver.install { _ in })
        XCTAssertEqual(driver.snapshot.phase, .closed)
        XCTAssertNil(driver.snapshot.scheduledMode)
    }

    func testInstallRejectsBackgroundThread() {
        let driver =
            IRSystemDisplayLinkDriver()
        let completed = expectation(
            description: "background install"
        )
        let result = LockedDisplayLinkBool()

        DispatchQueue.global().async {
            result.value = driver.install { _ in }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)

        XCTAssertFalse(result.value)
        XCTAssertEqual(
            driver.snapshot.phase,
            .uninstalled
        )
    }

    func testActivationRejectsBackgroundThread() {
        let driver =
            IRSystemDisplayLinkDriver()
        defer { driver.close() }
        XCTAssertTrue(driver.install { _ in })
        let completed = expectation(
            description: "background activation"
        )
        let result = LockedDisplayLinkBool()

        DispatchQueue.global().async {
            result.value = driver.setActive(true)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)

        XCTAssertFalse(result.value)
        XCTAssertEqual(driver.snapshot.phase, .idle)
    }

    func testActiveDriverClosesFromBackgroundThread() {
        let driver =
            IRSystemDisplayLinkDriver()
        var delivered = false
        XCTAssertTrue(
            driver.install { _ in
                delivered = true
            }
        )
        XCTAssertTrue(driver.setActive(true))
        let completed = expectation(
            description: "background close"
        )
        let result = LockedDisplayLinkBool()

        DispatchQueue.global().async {
            result.value = driver.close()
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        driver.emit(timestamp: 1)

        XCTAssertTrue(result.value)
        XCTAssertFalse(delivered)
        XCTAssertEqual(driver.snapshot.phase, .closed)
        XCTAssertNil(driver.snapshot.scheduledMode)
    }

    func testInstalledLinkDoesNotRetainDriver() {
        weak var weakDriver:
            IRSystemDisplayLinkDriver?

        autoreleasepool {
            var driver:
                IRSystemDisplayLinkDriver? =
                    IRSystemDisplayLinkDriver()
            XCTAssertTrue(driver?.install { _ in } == true)
            weakDriver = driver
            driver = nil
        }

        XCTAssertNil(weakDriver)
    }
}

private final class LockedDisplayLinkBool:
    @unchecked Sendable
{
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
