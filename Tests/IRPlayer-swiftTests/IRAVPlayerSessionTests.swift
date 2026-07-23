import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAVPlayerSessionTests: XCTestCase {
    func testActivationPublishesCompleteGraphAndOwnsObservationTokens() {
        let notificationCenter = NotificationCenter()
        let session = IRAVPlayerSession(
            notificationCenter: notificationCenter
        )
        let asset = makeAsset(named: "activation.mp4")

        let token = session.activate(
            asset: asset,
            automaticallyLoadedAssetKeys: nil,
            contentHeaders: nil,
            itemEventHandler: { _, _, _ in },
            periodicTimeHandler: { _, _ in }
        )

        XCTAssertNotNil(token)
        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .active)
        XCTAssertEqual(diagnostics.activationCount, 1)
        XCTAssertEqual(diagnostics.itemObservationCount, 3)
        XCTAssertTrue(diagnostics.hasAsset)
        XCTAssertTrue(diagnostics.hasItem)
        XCTAssertTrue(diagnostics.hasPlayer)
        XCTAssertFalse(diagnostics.hasOutput)
        XCTAssertTrue(diagnostics.hasEndObserver)
        XCTAssertTrue(diagnostics.hasPeriodicTimeObserver)

        XCTAssertTrue(
            session.withResources(default: false) { resources in
                resources.asset === asset &&
                    resources.player.currentItem === resources.item &&
                    resources.output == nil
            }
        )
        XCTAssertTrue(session.close())
    }

    func testActivationReplacesGenerationAndRejectsStaleIdentities() throws {
        let session = IRAVPlayerSession()
        let firstAsset = makeAsset(named: "first.mp4")
        let firstToken = try XCTUnwrap(
            activate(session, asset: firstAsset)
        )
        let firstResources = try XCTUnwrap(resourceSnapshot(session))

        let secondAsset = makeAsset(named: "second.mp4")
        let secondToken = try XCTUnwrap(
            activate(session, asset: secondAsset)
        )

        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertFalse(
            session.isCurrent(
                firstToken,
                asset: firstAsset,
                item: firstResources.item,
                player: firstResources.player
            )
        )
        XCTAssertTrue(
            session.isCurrent(secondToken, asset: secondAsset)
        )
        XCTAssertNil(firstResources.player.currentItem)
        XCTAssertEqual(session.diagnostics.activationCount, 2)
        XCTAssertTrue(session.close())
    }

    func testResetDrainsResourcesAndOwnedOutputExactlyOnce() throws {
        let session = IRAVPlayerSession()
        let token = try XCTUnwrap(
            activate(session, asset: makeAsset(named: "reset.mp4"))
        )
        XCTAssertTrue(session.rebuildVideoOutput(for: token))
        let resources = try XCTUnwrap(resourceSnapshot(session))
        let output = try XCTUnwrap(resources.output)
        XCTAssertTrue(resources.item.outputs.contains { $0 === output })

        XCTAssertTrue(session.reset())

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .empty)
        XCTAssertFalse(diagnostics.hasAsset)
        XCTAssertFalse(diagnostics.hasItem)
        XCTAssertFalse(diagnostics.hasPlayer)
        XCTAssertFalse(diagnostics.hasOutput)
        XCTAssertEqual(diagnostics.itemObservationCount, 0)
        XCTAssertFalse(diagnostics.hasEndObserver)
        XCTAssertFalse(diagnostics.hasPeriodicTimeObserver)
        XCTAssertEqual(diagnostics.resetCount, 1)
        XCTAssertNil(resources.player.currentItem)
        XCTAssertFalse(resources.item.outputs.contains { $0 === output })
        XCTAssertFalse(session.reset())
        XCTAssertTrue(session.close())
    }

    func testCloseIsConcurrentIdempotentAndRejectsActivation() {
        let session = IRAVPlayerSession()
        _ = activate(session, asset: makeAsset(named: "close.mp4"))
        let resultLock = NSLock()
        var ownerCount = 0

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard session.close() else { return }
            resultLock.lock()
            ownerCount += 1
            resultLock.unlock()
        }

        XCTAssertEqual(ownerCount, 1)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.close())
        XCTAssertNil(
            activate(session, asset: makeAsset(named: "rejected.mp4"))
        )
    }

    func testResetWaitsForExternalResourceLease() throws {
        let session = IRAVPlayerSession()
        _ = try XCTUnwrap(
            activate(session, asset: makeAsset(named: "lease.mp4"))
        )
        let leaseStarted = DispatchSemaphore(value: 0)
        let releaseLease = DispatchSemaphore(value: 0)
        let leaseFinished = expectation(description: "lease finished")
        let resetFinished = expectation(description: "reset finished")

        DispatchQueue.global(qos: .userInitiated).async {
            session.withResources(default: ()) { _ in
                leaseStarted.signal()
                releaseLease.wait()
            }
            leaseFinished.fulfill()
        }
        XCTAssertEqual(leaseStarted.wait(timeout: .now() + 2), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertTrue(session.reset())
            resetFinished.fulfill()
        }

        XCTAssertTrue(waitUntil { session.diagnostics.phase == .resetting })
        XCTAssertEqual(session.diagnostics.externalLeaseCount, 1)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(session.diagnostics.phase, .resetting)

        DispatchQueue.global(qos: .userInitiated).async {
            releaseLease.signal()
        }
        wait(for: [leaseFinished, resetFinished], timeout: 2)
        XCTAssertEqual(session.diagnostics.phase, .empty)
        XCTAssertTrue(session.close())
    }

    func testOutputRebuildWaitsForLeaseAndReplacesOwnedOutput() throws {
        let session = IRAVPlayerSession()
        let token = try XCTUnwrap(
            activate(session, asset: makeAsset(named: "output.mp4"))
        )
        XCTAssertTrue(session.rebuildVideoOutput(for: token))
        let firstResources = try XCTUnwrap(resourceSnapshot(session))
        let firstOutput = try XCTUnwrap(firstResources.output)
        let leaseStarted = DispatchSemaphore(value: 0)
        let releaseLease = DispatchSemaphore(value: 0)
        let rebuildFinished = expectation(description: "rebuild finished")

        DispatchQueue.global(qos: .userInitiated).async {
            session.withResources(default: ()) { _ in
                leaseStarted.signal()
                releaseLease.wait()
            }
        }
        XCTAssertEqual(leaseStarted.wait(timeout: .now() + 2), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertTrue(session.rebuildVideoOutput(for: token))
            rebuildFinished.fulfill()
        }

        XCTAssertTrue(
            waitUntil { session.diagnostics.phase == .reconfiguring }
        )
        XCTAssertEqual(session.diagnostics.externalLeaseCount, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            releaseLease.signal()
        }
        wait(for: [rebuildFinished], timeout: 2)

        let secondResources = try XCTUnwrap(resourceSnapshot(session))
        let secondOutput = try XCTUnwrap(secondResources.output)
        XCTAssertFalse(firstOutput === secondOutput)
        XCTAssertFalse(
            secondResources.item.outputs.contains { $0 === firstOutput }
        )
        XCTAssertTrue(
            secondResources.item.outputs.contains { $0 === secondOutput }
        )
        XCTAssertEqual(session.diagnostics.outputRebuildCount, 2)
        XCTAssertTrue(session.close())
    }

    func testEndNotificationIsDeliveredOnlyForCurrentItem() throws {
        let notificationCenter = NotificationCenter()
        let session = IRAVPlayerSession(
            notificationCenter: notificationCenter
        )
        var endedTokens: [IRAVPlayerSession.Token] = []
        let eventLock = NSLock()
        let currentItemEnded = expectation(
            description: "current item ended"
        )
        let handler: IRAVPlayerSession.ItemEventHandler = {
            token, _, event in
            guard case .didPlayToEnd = event else { return }
            eventLock.lock()
            endedTokens.append(token)
            eventLock.unlock()
            currentItemEnded.fulfill()
        }

        let firstToken = try XCTUnwrap(
            session.activate(
                asset: makeAsset(named: "ended-first.mp4"),
                automaticallyLoadedAssetKeys: nil,
                contentHeaders: nil,
                itemEventHandler: handler,
                periodicTimeHandler: { _, _ in }
            )
        )
        let firstItem = try XCTUnwrap(resourceSnapshot(session)?.item)
        let secondToken = try XCTUnwrap(
            session.activate(
                asset: makeAsset(named: "ended-second.mp4"),
                automaticallyLoadedAssetKeys: nil,
                contentHeaders: nil,
                itemEventHandler: handler,
                periodicTimeHandler: { _, _ in }
            )
        )
        let secondItem = try XCTUnwrap(resourceSnapshot(session)?.item)

        notificationCenter.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: firstItem
        )
        notificationCenter.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: secondItem
        )
        wait(for: [currentItemEnded], timeout: 1)

        eventLock.lock()
        let deliveredTokens = endedTokens
        eventLock.unlock()
        XCTAssertEqual(deliveredTokens, [secondToken])
        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertTrue(session.close())
    }

    func testStaleTokenCannotControlReplacementPlayer() throws {
        let session = IRAVPlayerSession()
        let firstToken = try XCTUnwrap(
            activate(session, asset: makeAsset(named: "control-first.mp4"))
        )
        let secondToken = try XCTUnwrap(
            activate(session, asset: makeAsset(named: "control-second.mp4"))
        )
        var staleBodyCalled = false
        var currentBodyCalled = false

        XCTAssertFalse(
            session.withCurrentPlayer(firstToken) { _ in
                staleBodyCalled = true
            }
        )
        XCTAssertTrue(
            session.withCurrentPlayer(secondToken) { _ in
                currentBodyCalled = true
            }
        )
        XCTAssertFalse(staleBodyCalled)
        XCTAssertTrue(currentBodyCalled)
        XCTAssertTrue(session.close())
    }

    func testAssetAndRedirectDecisionsLiveWithSessionOwner() throws {
        XCTAssertEqual(
            IRAVPlayerSession.assetLoadDecision(
                keyStatuses: [.loaded, .failed],
                trackStatus: .loaded
            ),
            .fail
        )
        XCTAssertEqual(
            IRAVPlayerSession.assetLoadDecision(
                keyStatuses: [.loaded, .loaded],
                trackStatus: .loaded
            ),
            .setupOutput
        )
        XCTAssertEqual(
            IRAVPlayerSession.assetLoadDecision(
                keyStatuses: [.loaded, .loading],
                trackStatus: .loading
            ),
            .ignore
        )

        let request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/video.m3u8"))
        )
        let redirected = try XCTUnwrap(
            IRAVPlayerSession.resourceLoaderRedirectRequest(
                for: request,
                headers: ["Authorization": "Bearer token"]
            )
        )
        XCTAssertEqual(
            redirected.value(forHTTPHeaderField: "Authorization"),
            "Bearer token"
        )
        XCTAssertNil(
            IRAVPlayerSession.resourceLoaderRedirectRequest(
                for: URLRequest(
                    url: URL(string: "http://example.com/video.m3u8")!
                ),
                headers: ["Authorization": "Bearer token"]
            )
        )
    }

    private func activate(
        _ session: IRAVPlayerSession,
        asset: AVURLAsset
    ) -> IRAVPlayerSession.Token? {
        session.activate(
            asset: asset,
            automaticallyLoadedAssetKeys: nil,
            contentHeaders: nil,
            itemEventHandler: { _, _, _ in },
            periodicTimeHandler: { _, _ in }
        )
    }

    private func resourceSnapshot(
        _ session: IRAVPlayerSession
    ) -> IRAVPlayerSession.Resources? {
        session.withResources(default: nil) { $0 }
    }

    private func makeAsset(named name: String) -> AVURLAsset {
        AVURLAsset(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(name)
        )
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
