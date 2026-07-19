import XCTest
@testable import IRPlayer_swift

final class IRPlayerEventTests: XCTestCase {
    func testStateNotificationAlsoEmitsTypedEvent() {
        let player = IRPlayer()
        player.manager = nil
        let expectation = expectation(description: "typed state event")
        let observation = player.observeEvents { event in
            guard case let .stateChanged(previous, current) = event else { return }
            XCTAssertEqual(previous, .buffering)
            XCTAssertEqual(current, .playing)
            expectation.fulfill()
        }

        IRPlayerNotification.postPlayer(player, statePrevious: .buffering, current: .playing)

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(observation) {}
    }

    func testProgressAndPlayableEventsUseTypedTimeSnapshots() {
        let player = IRPlayer()
        player.manager = nil
        let progressExpectation = expectation(description: "typed progress event")
        let playableExpectation = expectation(description: "typed playable event")
        let observation = player.observeEvents { event in
            switch event {
            case .progress(let snapshot):
                XCTAssertEqual(snapshot, IRPlayerTimeSnapshot(current: 3, total: 12, fraction: 0.25))
                progressExpectation.fulfill()
            case .playable(let snapshot):
                XCTAssertEqual(snapshot, IRPlayerTimeSnapshot(current: 6, total: 12, fraction: 0.5))
                playableExpectation.fulfill()
            default:
                break
            }
        }

        IRPlayerNotification.postPlayer(player, progressPercent: 0.25, current: 3, total: 12)
        IRPlayerNotification.postPlayer(player, playablePercent: 0.5, current: 6, total: 12)

        wait(for: [progressExpectation, playableExpectation], timeout: 1)
        withExtendedLifetime(observation) {}
    }

    func testFailureEventPreservesUnderlyingErrorModel() {
        let player = IRPlayer()
        player.manager = nil
        let expectedError = IRError()
        expectedError.error = NSError(domain: "IRPlayerEventTests", code: 7)
        let expectation = expectation(description: "typed failure event")
        let observation = player.observeEvents { event in
            guard case .failure(let error) = event else { return }
            XCTAssertTrue(error === expectedError)
            expectation.fulfill()
        }

        IRPlayerNotification.postPlayer(player, error: expectedError)

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(observation) {}
    }

    func testCancelledObservationDoesNotReceiveEvents() {
        let player = IRPlayer()
        player.manager = nil
        let expectation = expectation(description: "cancelled observer")
        expectation.isInverted = true
        let observation = player.observeEvents { _ in expectation.fulfill() }
        observation.cancel()

        IRPlayerNotification.postPlayer(player, statePrevious: .none, current: .buffering)

        wait(for: [expectation], timeout: 0.1)
    }

    func testEventsFromBackgroundAreDeliveredOnMainThread() {
        let emitter = IRPlayerEventEmitter()
        let expectation = expectation(description: "main event")
        let observation = emitter.observe { _ in
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }

        DispatchQueue.global().async {
            emitter.emit(.stateChanged(previous: .none, current: .buffering))
        }

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(observation) {}
    }
}
