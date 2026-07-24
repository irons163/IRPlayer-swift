import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRSmoothScrollDisplayLinkDriverTests:
    XCTestCase
{
    func testDriverStartsUninstalled() {
        let driver =
            IRSystemSmoothScrollDisplayLinkDriver()

        XCTAssertEqual(
            driver.snapshot,
            IRSmoothScrollDisplayLinkSnapshot(
                phase: .uninstalled,
                scheduledMode: nil
            )
        )
    }

    func testInstallSchedulesPausedCommonModeLink() {
        let driver =
            IRSystemSmoothScrollDisplayLinkDriver()
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
            IRSystemSmoothScrollDisplayLinkDriver()
        defer { driver.close() }

        XCTAssertTrue(driver.install { _ in })
        XCTAssertFalse(driver.install { _ in })
        XCTAssertEqual(driver.snapshot.phase, .idle)
    }

    func testActiveAndPausedPhasesControlDelivery() {
        let driver =
            IRSystemSmoothScrollDisplayLinkDriver()
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
            IRSystemSmoothScrollDisplayLinkDriver()
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
            IRSystemSmoothScrollDisplayLinkDriver()
        let completed = expectation(
            description: "background install"
        )
        let result = LockedSmoothScrollBool()

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

    func testInstalledLinkDoesNotRetainDriver() {
        weak var weakDriver:
            IRSystemSmoothScrollDisplayLinkDriver?

        autoreleasepool {
            var driver:
                IRSystemSmoothScrollDisplayLinkDriver? =
                    IRSystemSmoothScrollDisplayLinkDriver()
            XCTAssertTrue(driver?.install { _ in } == true)
            weakDriver = driver
            driver = nil
        }

        XCTAssertNil(weakDriver)
    }
}

private final class LockedSmoothScrollBool:
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
