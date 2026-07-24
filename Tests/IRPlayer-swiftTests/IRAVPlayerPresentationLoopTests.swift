import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAVPlayerPresentationLoopTests:
    XCTestCase
{
    func testLoopStartsUninstalled() {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )

        XCTAssertEqual(
            loop.diagnostics,
            IRAVPlayerPresentationLoop.Diagnostics(
                phase: .uninstalled,
                generation: 0,
                activePresentationToken: nil,
                hasActiveSessionToken: false,
                driver: driver.snapshot,
                installationCount: 0,
                activationCount: 0,
                deactivationCount: 0,
                deliveredTickCount: 0,
                rejectedTickCount: 0,
                closeCount: 0
            )
        )
    }

    func testInstallPublishesIdleAndRejectsDuplicate() {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )

        XCTAssertTrue(loop.install { _ in })
        XCTAssertFalse(loop.install { _ in })

        let diagnostics = loop.diagnostics
        XCTAssertEqual(diagnostics.phase, .idle)
        XCTAssertEqual(diagnostics.installationCount, 1)
        XCTAssertEqual(diagnostics.driver.phase, .idle)
        XCTAssertEqual(driver.installCount, 1)
    }

    func testInstallationFailureLeavesLoopUninstalled() {
        let driver = AVDisplayLinkProbe(
            installsSuccessfully: false
        )
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )

        XCTAssertFalse(loop.install { _ in })
        XCTAssertEqual(
            loop.diagnostics.phase,
            .uninstalled
        )
        XCTAssertNil(
            loop.activate(
                sessionToken: makeSessionToken()
            )
        )
    }

    func testActivationBindsTickToExactSessionToken() throws {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        let sessionToken = makeSessionToken()
        var ticks: [IRAVPlayerPresentationLoop.Tick] = []
        XCTAssertTrue(loop.install { ticks.append($0) })

        let presentationToken = try XCTUnwrap(
            loop.activate(sessionToken: sessionToken)
        )
        driver.emit(timestamp: 12.5)

        let tick = try XCTUnwrap(ticks.first)
        XCTAssertEqual(
            tick.presentationToken,
            presentationToken
        )
        XCTAssertEqual(tick.sessionToken, sessionToken)
        XCTAssertEqual(tick.timestamp, 12.5)
        XCTAssertTrue(loop.isCurrent(tick))
        XCTAssertEqual(
            driver.activeRequests,
            [true]
        )
    }

    func testActivationFailurePreservesIdleState() {
        let driver = AVDisplayLinkProbe(
            activatesSuccessfully: false
        )
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        XCTAssertTrue(loop.install { _ in })

        XCTAssertNil(
            loop.activate(
                sessionToken: makeSessionToken()
            )
        )

        let diagnostics = loop.diagnostics
        XCTAssertEqual(diagnostics.phase, .idle)
        XCTAssertEqual(diagnostics.generation, 0)
        XCTAssertEqual(diagnostics.activationCount, 0)
        XCTAssertFalse(
            diagnostics.hasActiveSessionToken
        )
    }

    func testDeactivateRevokesCapturedTickBeforePausing()
        throws
    {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        var capturedTick:
            IRAVPlayerPresentationLoop.Tick?
        XCTAssertTrue(
            loop.install { capturedTick = $0 }
        )
        XCTAssertNotNil(
            loop.activate(
                sessionToken: makeSessionToken()
            )
        )
        driver.emit(timestamp: 1)
        let staleTick = try XCTUnwrap(capturedTick)

        XCTAssertTrue(loop.deactivate())
        XCTAssertFalse(loop.deactivate())
        driver.emitRegardless(timestamp: 2)

        XCTAssertFalse(loop.isCurrent(staleTick))
        XCTAssertEqual(
            driver.activeRequests,
            [true, false]
        )
        let diagnostics = loop.diagnostics
        XCTAssertEqual(diagnostics.phase, .idle)
        XCTAssertEqual(diagnostics.generation, 2)
        XCTAssertEqual(diagnostics.deactivationCount, 1)
        XCTAssertEqual(diagnostics.deliveredTickCount, 1)
        XCTAssertEqual(diagnostics.rejectedTickCount, 1)
    }

    func testDeactivateRevokesOwnerWhenDriverPauseFails() {
        let driver = AVDisplayLinkProbe(
            deactivatesSuccessfully: false
        )
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        var deliveredTickCount = 0
        XCTAssertTrue(
            loop.install { _ in
                deliveredTickCount += 1
            }
        )
        XCTAssertNotNil(
            loop.activate(
                sessionToken: makeSessionToken()
            )
        )

        XCTAssertTrue(loop.deactivate())
        driver.emit(timestamp: 2)

        let diagnostics = loop.diagnostics
        XCTAssertEqual(diagnostics.phase, .idle)
        XCTAssertEqual(diagnostics.driver.phase, .active)
        XCTAssertEqual(diagnostics.deactivationCount, 1)
        XCTAssertEqual(diagnostics.rejectedTickCount, 1)
        XCTAssertEqual(deliveredTickCount, 0)
    }

    func testReactivationRejectsPriorPresentationGeneration()
        throws
    {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        let sessionTokens = makeSessionTokens(
            named: ["first.mp4", "second.mp4"]
        )
        var ticks: [IRAVPlayerPresentationLoop.Tick] = []
        XCTAssertTrue(loop.install { ticks.append($0) })

        XCTAssertNotNil(
            loop.activate(
                sessionToken: sessionTokens[0]
            )
        )
        driver.emit(timestamp: 1)
        let firstTick = try XCTUnwrap(ticks.last)
        XCTAssertTrue(loop.deactivate())

        XCTAssertNotNil(
            loop.activate(
                sessionToken: sessionTokens[1]
            )
        )
        driver.emit(timestamp: 2)
        let secondTick = try XCTUnwrap(ticks.last)

        XCTAssertFalse(loop.isCurrent(firstTick))
        XCTAssertTrue(loop.isCurrent(secondTick))
        XCTAssertNotEqual(
            firstTick.presentationToken,
            secondTick.presentationToken
        )
        XCTAssertNotEqual(
            firstTick.sessionToken,
            secondTick.sessionToken
        )
    }

    func testInvalidTimestampsAreRejected() {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        var ticks: [IRAVPlayerPresentationLoop.Tick] = []
        XCTAssertTrue(loop.install { ticks.append($0) })
        XCTAssertNotNil(
            loop.activate(
                sessionToken: makeSessionToken()
            )
        )

        driver.emitRegardless(timestamp: .nan)
        driver.emitRegardless(timestamp: -1)

        XCTAssertTrue(ticks.isEmpty)
        XCTAssertEqual(
            loop.diagnostics.rejectedTickCount,
            2
        )
    }

    func testCloseIsTerminalRepeatableAndRejectsStaleTicks()
        throws
    {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        var capturedTick:
            IRAVPlayerPresentationLoop.Tick?
        XCTAssertTrue(
            loop.install { capturedTick = $0 }
        )
        XCTAssertNotNil(
            loop.activate(
                sessionToken: makeSessionToken()
            )
        )
        driver.emit(timestamp: 1)
        let staleTick = try XCTUnwrap(capturedTick)

        XCTAssertTrue(loop.close())
        XCTAssertFalse(loop.close())
        driver.emitRegardless(timestamp: 2)

        XCTAssertFalse(loop.isCurrent(staleTick))
        XCTAssertNil(
            loop.activate(
                sessionToken: makeSessionToken()
            )
        )
        let diagnostics = loop.diagnostics
        XCTAssertEqual(diagnostics.phase, .closed)
        XCTAssertEqual(diagnostics.driver.phase, .closed)
        XCTAssertEqual(diagnostics.closeCount, 1)
        XCTAssertEqual(driver.closeCount, 1)
    }

    func testConcurrentLifecycleAndTickMutationRemainCoherent() {
        let driver = AVDisplayLinkProbe()
        let loop = IRAVPlayerPresentationLoop(
            driver: driver
        )
        let sessionTokens = makeSessionTokens(
            named: [
                "concurrent-first.mp4",
                "concurrent-second.mp4"
            ]
        )
        XCTAssertTrue(loop.install { tick in
            _ = loop.isCurrent(tick)
        })

        DispatchQueue.concurrentPerform(
            iterations: 300
        ) { index in
            switch index % 3 {
            case 0:
                _ = loop.activate(
                    sessionToken:
                        index.isMultiple(of: 2)
                        ? sessionTokens[0]
                        : sessionTokens[1]
                )
            case 1:
                driver.emitRegardless(
                    timestamp: TimeInterval(index)
                )
            default:
                _ = loop.deactivate()
            }
            _ = loop.diagnostics
        }

        XCTAssertTrue(loop.close())
        let diagnostics = loop.diagnostics
        XCTAssertEqual(diagnostics.phase, .closed)
        XCTAssertNil(
            diagnostics.activePresentationToken
        )
        XCTAssertFalse(
            diagnostics.hasActiveSessionToken
        )
    }

    func testDriverDoesNotRetainPresentationLoop() {
        let driver = AVDisplayLinkProbe()
        weak var weakLoop:
            IRAVPlayerPresentationLoop?

        autoreleasepool {
            var loop:
                IRAVPlayerPresentationLoop? =
                    IRAVPlayerPresentationLoop(
                        driver: driver
                    )
            XCTAssertTrue(loop?.install { _ in } == true)
            weakLoop = loop
            loop = nil
        }

        XCTAssertNil(weakLoop)
        XCTAssertEqual(driver.closeCount, 1)
        XCTAssertEqual(driver.snapshot.phase, .closed)
    }
}

private final class AVDisplayLinkProbe:
    IRDisplayLinkDriving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let installsSuccessfully: Bool
    private let activatesSuccessfully: Bool
    private let deactivatesSuccessfully: Bool
    private var storedSnapshot =
        IRDisplayLinkSnapshot(
            phase: .uninstalled,
            scheduledMode: nil
        )
    private var handler:
        ((TimeInterval) -> Void)?
    private var storedInstallCount = 0
    private var storedCloseCount = 0
    private var storedActiveRequests: [Bool] = []

    init(
        installsSuccessfully: Bool = true,
        activatesSuccessfully: Bool = true,
        deactivatesSuccessfully: Bool = true
    ) {
        self.installsSuccessfully =
            installsSuccessfully
        self.activatesSuccessfully =
            activatesSuccessfully
        self.deactivatesSuccessfully =
            deactivatesSuccessfully
    }

    var snapshot: IRDisplayLinkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    var installCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedInstallCount
    }

    var closeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCloseCount
    }

    var activeRequests: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storedActiveRequests
    }

    @discardableResult
    func install(
        handler: @escaping (TimeInterval) -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storedInstallCount += 1
        guard installsSuccessfully,
              storedSnapshot.phase == .uninstalled else {
            return false
        }
        self.handler = handler
        storedSnapshot =
            IRDisplayLinkSnapshot(
                phase: .idle,
                scheduledMode:
                    RunLoop.Mode.common.rawValue
            )
        return true
    }

    @discardableResult
    func setActive(_ isActive: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedSnapshot.phase == .idle
                || storedSnapshot.phase == .active,
              isActive
                ? activatesSuccessfully
                : deactivatesSuccessfully else {
            return false
        }
        storedActiveRequests.append(isActive)
        storedSnapshot =
            IRDisplayLinkSnapshot(
                phase: isActive ? .active : .idle,
                scheduledMode:
                    RunLoop.Mode.common.rawValue
            )
        return true
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedSnapshot.phase != .closed else {
            return false
        }
        storedCloseCount += 1
        handler = nil
        storedSnapshot =
            IRDisplayLinkSnapshot(
                phase: .closed,
                scheduledMode: nil
            )
        return true
    }

    func emit(timestamp: TimeInterval) {
        let handler: ((TimeInterval) -> Void)?
        lock.lock()
        handler = storedSnapshot.phase == .active
            ? self.handler
            : nil
        lock.unlock()
        handler?(timestamp)
    }

    func emitRegardless(timestamp: TimeInterval) {
        let handler: ((TimeInterval) -> Void)?
        lock.lock()
        handler = self.handler
        lock.unlock()
        handler?(timestamp)
    }
}

private func makeSessionToken(
    named name: String = "presentation-loop.mp4"
) -> IRAVPlayerSession.Token {
    makeSessionTokens(named: [name])[0]
}

private func makeSessionTokens(
    named names: [String]
) -> [IRAVPlayerSession.Token] {
    let session = IRAVPlayerSession()
    defer { session.close() }
    let tokens = names.compactMap { name in
        let asset = AVURLAsset(
            url: URL(
                fileURLWithPath: "/tmp/\(name)"
            )
        )
        return session.activate(
            asset: asset,
            automaticallyLoadedAssetKeys: nil,
            contentHeaders: nil,
            itemEventHandler: { _, _, _ in },
            periodicTimeHandler: { _, _ in }
        )
    }
    precondition(
        tokens.count == names.count,
        "Test fixture could not activate every AVPlayer session."
    )
    return tokens
}
