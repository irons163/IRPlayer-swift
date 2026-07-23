import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAudioGraphSessionTests: XCTestCase {
    func testPreparePublishesCompleteGraphAndConfiguresRenderContext() {
        let driver = TestAudioGraphDriver()
        let session = IRAudioGraphSession(driver: driver)

        XCTAssertTrue(session.prepare(preferredSampleRate: 48_000))

        let diagnostics = session.diagnostics
        XCTAssertEqual(diagnostics.phase, .ready)
        XCTAssertTrue(diagnostics.hasGraph)
        XCTAssertTrue(diagnostics.hasMixerAudioUnit)
        XCTAssertEqual(diagnostics.prepareCount, 1)
        XCTAssertEqual(diagnostics.renderContext.sampleRate, 48_000)
        XCTAssertEqual(diagnostics.renderContext.channelCount, 2)
        XCTAssertEqual(driver.buildCount, 1)
    }

    func testPrepareIsIdempotentAndFailedBuildCanRetry() {
        let driver = TestAudioGraphDriver()
        let failure = IRAudioGraphBuildFailure(
            issue: IRAudioGraphIssue(
                stage: .setMixerOutputFormat,
                status: -10
            ),
            cleanupIssues: [
                IRAudioGraphIssue(stage: .closeGraph, status: -11)
            ]
        )
        driver.replaceBuildResults([
            .failure(failure),
            .success(
                IRAudioGraphBuildOutput(
                    resources: makeTestAudioGraphResources(),
                    warnings: []
                )
            )
        ])
        let session = IRAudioGraphSession(driver: driver)

        XCTAssertFalse(session.prepare(preferredSampleRate: 48_000))
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertEqual(session.diagnostics.lastBuildFailure, failure)
        XCTAssertEqual(session.diagnostics.warnings, failure.cleanupIssues)

        XCTAssertTrue(session.prepare(preferredSampleRate: 48_000))
        XCTAssertTrue(session.prepare(preferredSampleRate: 48_000))
        XCTAssertEqual(driver.buildCount, 2)
        XCTAssertEqual(session.diagnostics.prepareCount, 1)
    }

    func testStartFailureKeepsReadyGraphAndDeactivatesCallback() {
        let driver = TestAudioGraphDriver()
        driver.startIssue = IRAudioGraphIssue(
            stage: .startGraph,
            status: -20
        )
        let session = IRAudioGraphSession(driver: driver)
        let manager = makeManager(session: session)
        let delegate = TestAudioManagerDelegate()

        XCTAssertFalse(
            session.start(
                owner: manager,
                delegate: delegate,
                preferredSampleRate: 48_000
            )
        )

        XCTAssertEqual(session.diagnostics.phase, .ready)
        XCTAssertFalse(session.diagnostics.renderContext.active)
        XCTAssertEqual(
            session.diagnostics.lastOperationalIssue,
            driver.startIssue
        )
        XCTAssertEqual(driver.startCount, 1)
    }

    func testStartUpdatesDelegateWithoutRestartingRunningGraph() {
        let driver = TestAudioGraphDriver()
        let session = IRAudioGraphSession(driver: driver)
        let manager = makeManager(session: session)
        let first = TestAudioManagerDelegate()
        let second = TestAudioManagerDelegate()

        XCTAssertTrue(
            session.start(
                owner: manager,
                delegate: first,
                preferredSampleRate: 48_000
            )
        )
        XCTAssertTrue(
            session.start(
                owner: manager,
                delegate: second,
                preferredSampleRate: 48_000
            )
        )

        XCTAssertTrue(session.renderContext.currentDelegate === second)
        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(session.diagnostics.startCount, 1)
    }

    func testPauseDeactivatesBeforeStoppingAndIsRepeatable() {
        let driver = TestAudioGraphDriver()
        let session = IRAudioGraphSession(driver: driver)
        let manager = makeManager(session: session)
        let delegate = TestAudioManagerDelegate()
        XCTAssertTrue(
            session.start(
                owner: manager,
                delegate: delegate,
                preferredSampleRate: 48_000
            )
        )

        XCTAssertTrue(session.pause())
        XCTAssertFalse(session.pause())

        XCTAssertEqual(session.diagnostics.phase, .ready)
        XCTAssertFalse(session.diagnostics.renderContext.active)
        XCTAssertEqual(session.diagnostics.pauseCount, 1)
        XCTAssertEqual(driver.stopCount, 1)
    }

    func testStopFailureStillRejectsRenderingAndRecordsWarning() {
        let driver = TestAudioGraphDriver()
        let issue = IRAudioGraphIssue(stage: .stopGraph, status: -30)
        driver.stopIssue = issue
        let session = IRAudioGraphSession(driver: driver)
        let manager = makeManager(session: session)
        let delegate = TestAudioManagerDelegate()
        XCTAssertTrue(
            session.start(
                owner: manager,
                delegate: delegate,
                preferredSampleRate: 48_000
            )
        )

        XCTAssertFalse(session.pause())

        XCTAssertEqual(session.diagnostics.phase, .ready)
        XCTAssertEqual(session.diagnostics.lastOperationalIssue, issue)
        XCTAssertTrue(session.diagnostics.warnings.contains(issue))
        XCTAssertFalse(session.diagnostics.renderContext.active)
    }

    func testResetStopsRunningGraphBeforeSingleTeardownAndAllowsReuse() {
        let driver = TestAudioGraphDriver()
        let session = IRAudioGraphSession(driver: driver)
        let manager = makeManager(session: session)
        XCTAssertTrue(
            session.start(
                owner: manager,
                delegate: TestAudioManagerDelegate(),
                preferredSampleRate: 48_000
            )
        )

        XCTAssertTrue(session.reset())
        XCTAssertFalse(session.reset())

        XCTAssertEqual(driver.events, ["build", "start", "stop", "teardown"])
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertFalse(session.diagnostics.hasGraph)
        XCTAssertEqual(session.diagnostics.resetCount, 1)
        XCTAssertEqual(session.diagnostics.teardownCount, 1)

        XCTAssertTrue(session.prepare(preferredSampleRate: 44_100))
        XCTAssertEqual(driver.buildCount, 2)
    }

    func testConcurrentPrepareBuildsOnlyOneGraph() {
        let driver = TestAudioGraphDriver()
        let buildEntered = DispatchSemaphore(value: 0)
        let resumeBuild = DispatchSemaphore(value: 0)
        driver.onBuild = {
            buildEntered.signal()
            _ = resumeBuild.wait(timeout: .now() + 2)
        }
        let session = IRAudioGraphSession(driver: driver)
        let resultLock = NSLock()
        var results: [Bool] = []
        let group = DispatchGroup()

        for _ in 0..<12 {
            group.enter()
            DispatchQueue.global().async {
                let result = session.prepare(preferredSampleRate: 48_000)
                resultLock.lock()
                results.append(result)
                resultLock.unlock()
                group.leave()
            }
        }
        XCTAssertEqual(buildEntered.wait(timeout: .now() + 1), .success)
        resumeBuild.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)

        XCTAssertEqual(results.count, 12)
        XCTAssertTrue(results.allSatisfy { $0 })
        XCTAssertEqual(driver.buildCount, 1)
    }

    func testConcurrentCloseElectsOneTeardownOwnerAndRejectsReuse() {
        let driver = TestAudioGraphDriver()
        let session = IRAudioGraphSession(driver: driver)
        XCTAssertTrue(session.prepare(preferredSampleRate: 48_000))
        let resultLock = NSLock()
        var ownerCount = 0
        let group = DispatchGroup()

        for _ in 0..<16 {
            group.enter()
            DispatchQueue.global().async {
                let ownedClose = session.close()
                resultLock.lock()
                if ownedClose {
                    ownerCount += 1
                }
                resultLock.unlock()
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)

        XCTAssertEqual(ownerCount, 1)
        XCTAssertEqual(driver.teardownCount, 1)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.prepare(preferredSampleRate: 48_000))
    }

    func testCloseWaitsForAdmittedRenderBeforeStopAndTeardown() {
        let driver = TestAudioGraphDriver()
        let session = IRAudioGraphSession(driver: driver)
        let manager = makeManager(session: session)
        let delegate = TestAudioManagerDelegate()
        let renderEntered = DispatchSemaphore(value: 0)
        let resumeRender = DispatchSemaphore(value: 0)
        delegate.render = { _, _, _ in
            renderEntered.signal()
            _ = resumeRender.wait(timeout: .now() + 2)
        }
        XCTAssertTrue(
            session.start(
                owner: manager,
                delegate: delegate,
                preferredSampleRate: 48_000
            )
        )

        let renderFinished = expectation(description: "render")
        DispatchQueue.global().async {
            var samples = [Float](repeating: 0, count: 4)
            samples.withUnsafeMutableBufferPointer { buffer in
                guard let address = buffer.baseAddress else { return }
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 2,
                        mDataByteSize: UInt32(
                            buffer.count * MemoryLayout<Float>.stride
                        ),
                        mData: address
                    )
                )
                _ = withUnsafeMutablePointer(to: &list) {
                    session.renderFrames(2, ioData: $0)
                }
            }
            renderFinished.fulfill()
        }
        XCTAssertEqual(renderEntered.wait(timeout: .now() + 1), .success)

        let closeFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = session.close()
            closeFinished.signal()
        }
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )
        XCTAssertEqual(driver.stopCount, 0)
        XCTAssertEqual(driver.teardownCount, 0)

        resumeRender.signal()
        wait(for: [renderFinished], timeout: 2)
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(driver.events, ["build", "start", "stop", "teardown"])
        XCTAssertEqual(session.diagnostics.phase, .closed)
    }

    func testVolumeFailuresReturnFallbackAndRemainDiagnosable() {
        let driver = TestAudioGraphDriver()
        let getIssue = IRAudioGraphIssue(stage: .getVolume, status: -40)
        let setIssue = IRAudioGraphIssue(stage: .setVolume, status: -41)
        driver.volumeIssue = getIssue
        driver.setVolumeIssue = setIssue
        let session = IRAudioGraphSession(driver: driver)
        XCTAssertTrue(session.prepare(preferredSampleRate: 48_000))

        XCTAssertEqual(session.volume(default: 0.25), 0.25)
        XCTAssertEqual(session.diagnostics.lastOperationalIssue, getIssue)
        session.setVolume(0.5)
        XCTAssertEqual(session.diagnostics.lastOperationalIssue, setIssue)
    }

    private func makeManager(
        session: IRAudioGraphSession
    ) -> IRAudioManager {
        IRAudioManager(
            graphSession: session,
            hardwareInfo: IRAudioHardwareInfo(
                sampleRate: { 48_000 },
                channelCount: { 2 }
            ),
            notificationCenter: NotificationCenter()
        )
    }
}
