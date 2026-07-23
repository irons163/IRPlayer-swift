import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAudioManagerRenderTests: XCTestCase {
    func testUnpreparedRenderClearsDestinationAndReturnsSilence() throws {
        let manager = makeTestAudioManager()
        var samples: [Float] = [1, -0.5, 0.25, 2]

        withInterleavedAudioBufferList(
            values: &samples,
            channels: 2
        ) { bufferList in
            XCTAssertEqual(
                manager.renderFrames(2, ioData: bufferList),
                noErr
            )
        }

        XCTAssertEqual(samples, [0, 0, 0, 0])
    }

    func testFloat32InterleavedRenderCopiesDelegateSamples() throws {
        let manager = makeTestAudioManager()
        let delegate = TestAudioManagerDelegate()
        delegate.render = { output, frames, channels in
            let count = Int(frames * channels)
            for index in 0..<count {
                output[index] = Float(index + 1)
            }
        }
        XCTAssertTrue(manager.play(withDelegate: delegate))
        defer { manager.pause() }
        var samples = [Float](repeating: -1, count: 4)

        withInterleavedAudioBufferList(
            values: &samples,
            channels: 2
        ) { bufferList in
            XCTAssertEqual(
                manager.renderFrames(2, ioData: bufferList),
                noErr
            )
        }

        XCTAssertEqual(samples, [1, 2, 3, 4])
        XCTAssertEqual(delegate.renderCount, 1)
    }

    func testScratchBufferIsSilencedBeforePartialDelegateFill() throws {
        let manager = makeTestAudioManager()
        let delegate = TestAudioManagerDelegate()
        delegate.render = { output, _, _ in
            output[0] = 0.5
        }
        XCTAssertTrue(manager.play(withDelegate: delegate))
        defer { manager.pause() }
        var samples = [Float](repeating: -1, count: 4)

        withInterleavedAudioBufferList(
            values: &samples,
            channels: 2
        ) { bufferList in
            _ = manager.renderFrames(2, ioData: bufferList)
        }

        XCTAssertEqual(samples, [0.5, 0, 0, 0])
    }

    func testFloat32NonInterleavedRenderMaintainsGlobalChannelMapping()
        throws
    {
        let format = makeTestPCMFormat(
            flags: kAudioFormatFlagIsFloat |
                kAudioFormatFlagIsPacked |
                kAudioFormatFlagIsNonInterleaved
        )
        let manager = makeTestAudioManager(
            driver: TestAudioGraphDriver(format: format)
        )
        let delegate = TestAudioManagerDelegate()
        delegate.render = { output, _, _ in
            output[0] = 1
            output[1] = 10
            output[2] = 2
            output[3] = 20
        }
        XCTAssertTrue(manager.play(withDelegate: delegate))
        defer { manager.pause() }
        var left = [Float](repeating: -1, count: 2)
        var right = [Float](repeating: -1, count: 2)

        try left.withUnsafeMutableBufferPointer { leftBuffer in
            try right.withUnsafeMutableBufferPointer { rightBuffer in
                let leftAddress = try XCTUnwrap(leftBuffer.baseAddress)
                let rightAddress = try XCTUnwrap(rightBuffer.baseAddress)
                withAudioBufferList(
                    buffers: [
                        AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: UInt32(
                                leftBuffer.count *
                                    MemoryLayout<Float>.stride
                            ),
                            mData: leftAddress
                        ),
                        AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: UInt32(
                                rightBuffer.count *
                                    MemoryLayout<Float>.stride
                            ),
                            mData: rightAddress
                        )
                    ]
                ) { bufferList in
                    _ = manager.renderFrames(2, ioData: bufferList)
                }
            }
        }

        XCTAssertEqual(left, [1, 2])
        XCTAssertEqual(right, [10, 20])
    }

    func testUndersizedDestinationIsSilencedOnlyWithinDeclaredCapacity()
        throws
    {
        let manager = makeTestAudioManager()
        let delegate = TestAudioManagerDelegate()
        delegate.render = { output, _, _ in
            output[0] = 1
            output[1] = 2
            output[2] = 3
            output[3] = 4
        }
        XCTAssertTrue(manager.play(withDelegate: delegate))
        defer { manager.pause() }
        var samples: [Float] = [9, 8, 7, 6]

        try samples.withUnsafeMutableBufferPointer { buffer in
            let address = try XCTUnwrap(buffer.baseAddress)
            withAudioBufferList(
                buffers: [
                    AudioBuffer(
                        mNumberChannels: 2,
                        mDataByteSize: UInt32(MemoryLayout<Float>.stride),
                        mData: address
                    )
                ]
            ) { bufferList in
                _ = manager.renderFrames(2, ioData: bufferList)
            }
        }

        XCTAssertEqual(samples, [0, 8, 7, 6])
    }

    func testInt16RenderClampsBeforeConversion() throws {
        let format = makeTestPCMFormat(
            bitsPerChannel: 16,
            flags: kAudioFormatFlagIsSignedInteger |
                kAudioFormatFlagIsPacked
        )
        let driver = TestAudioGraphDriver(format: format)
        let manager = makeTestAudioManager(driver: driver)
        let delegate = TestAudioManagerDelegate()
        delegate.render = { output, _, _ in
            output[0] = -2
            output[1] = -0.5
            output[2] = 0.5
            output[3] = 2
        }
        XCTAssertTrue(manager.play(withDelegate: delegate))
        defer { manager.pause() }
        var samples = [Int16](repeating: 0, count: 4)

        withInterleavedAudioBufferList(
            values: &samples,
            channels: 2
        ) { bufferList in
            _ = manager.renderFrames(2, ioData: bufferList)
        }

        XCTAssertEqual(samples[0], -Int16.max)
        XCTAssertLessThanOrEqual(abs(Int(samples[1]) + 16_384), 1)
        XCTAssertLessThanOrEqual(abs(Int(samples[2]) - 16_384), 1)
        XCTAssertEqual(samples[3], Int16.max)
    }

    func testOversizedRenderRequestReturnsDeclaredDestinationSilence()
        throws
    {
        let manager = makeTestAudioManager()
        let delegate = TestAudioManagerDelegate()
        XCTAssertTrue(manager.play(withDelegate: delegate))
        defer { manager.pause() }
        var samples: [Float] = [4, 3, 2, 1]

        withInterleavedAudioBufferList(
            values: &samples,
            channels: 2
        ) { bufferList in
            _ = manager.renderFrames(
                IRAudioRenderContext.defaultMaximumFrames + 1,
                ioData: bufferList
            )
        }

        XCTAssertEqual(samples, [0, 0, 0, 0])
        XCTAssertEqual(delegate.renderCount, 0)
    }

    func testContendedRenderCallbackReturnsSilenceWithoutWaiting()
        throws
    {
        let manager = makeTestAudioManager()
        let delegate = TestAudioManagerDelegate()
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        delegate.render = { output, frames, channels in
            entered.signal()
            _ = resume.wait(timeout: .now() + 2)
            let count = Int(frames * channels)
            for index in 0..<count {
                output[index] = 1
            }
        }
        XCTAssertTrue(manager.play(withDelegate: delegate))
        defer { manager.pause() }

        let firstFinished = expectation(description: "first render")
        DispatchQueue.global().async {
            var first = [Float](repeating: -1, count: 4)
            first.withUnsafeMutableBufferPointer { buffer in
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
                    manager.renderFrames(2, ioData: $0)
                }
            }
            firstFinished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)

        var second = [Float](repeating: 7, count: 4)
        withInterleavedAudioBufferList(
            values: &second,
            channels: 2
        ) { bufferList in
            _ = manager.renderFrames(2, ioData: bufferList)
        }
        XCTAssertEqual(second, [0, 0, 0, 0])

        resume.signal()
        wait(for: [firstFinished], timeout: 2)
    }

    func testPauseWaitsForAdmittedRenderBeforeReturning() {
        let manager = makeTestAudioManager()
        let delegate = TestAudioManagerDelegate()
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        delegate.render = { _, _, _ in
            entered.signal()
            _ = resume.wait(timeout: .now() + 2)
        }
        XCTAssertTrue(manager.play(withDelegate: delegate))

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
                    manager.renderFrames(2, ioData: $0)
                }
            }
            renderFinished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)

        let pauseReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            manager.pause()
            pauseReturned.signal()
        }
        XCTAssertEqual(
            pauseReturned.wait(timeout: .now() + 0.05),
            .timedOut
        )

        resume.signal()
        wait(for: [renderFinished], timeout: 2)
        XCTAssertEqual(
            pauseReturned.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertFalse(manager.playing)
    }

    func testRenderSampleCountRejectsInvalidOverflowAndCapacity() {
        XCTAssertNil(
            IRAudioManager.renderSampleCount(
                numberOfFrames: 0,
                numberOfChannels: 2
            )
        )
        XCTAssertNil(
            IRAudioManager.renderSampleCount(
                numberOfFrames: .max,
                numberOfChannels: .max
            )
        )
        XCTAssertNil(
            IRAudioManager.renderSampleCount(
                numberOfFrames: 4_097,
                numberOfChannels: 2,
                maximumSampleCount: 4_096 * 2
            )
        )
        XCTAssertEqual(
            IRAudioManager.renderSampleCount(
                numberOfFrames: 10,
                numberOfChannels: 2
            ),
            20
        )
    }

    func testRealGraphPrepareAndResetEitherSucceedsOrFailsCleanly() {
        let manager = IRAudioManager()

        let prepared = manager.registerAudioSession()
        if prepared {
            XCTAssertEqual(manager.diagnostics.phase, .ready)
            XCTAssertGreaterThan(manager.samplingRate, 0)
            XCTAssertGreaterThan(manager.numberOfChannels, 0)
        } else {
            XCTAssertEqual(manager.diagnostics.phase, .idle)
            XCTAssertNotNil(manager.diagnostics.lastBuildFailure)
        }

        manager.unregisterAudioSession()
        XCTAssertEqual(manager.diagnostics.phase, .idle)
        XCTAssertFalse(manager.playing)
    }

    private func withInterleavedAudioBufferList<Element>(
        values: inout [Element],
        channels: UInt32,
        body: (UnsafeMutablePointer<AudioBufferList>) throws -> Void
    ) rethrows {
        try values.withUnsafeMutableBufferPointer { buffer in
            guard let address = buffer.baseAddress else { return }
            let audioBuffer = AudioBuffer(
                mNumberChannels: channels,
                mDataByteSize: UInt32(
                    buffer.count * MemoryLayout<Element>.stride
                ),
                mData: address
            )
            try withAudioBufferList(buffers: [audioBuffer], body: body)
        }
    }

    private func withAudioBufferList(
        buffers: [AudioBuffer],
        body: (UnsafeMutablePointer<AudioBufferList>) throws -> Void
    ) rethrows {
        let list = AudioBufferList.allocate(
            maximumBuffers: buffers.count
        )
        defer { free(list.unsafeMutablePointer) }
        list.count = buffers.count
        for (index, buffer) in buffers.enumerated() {
            list[index] = buffer
        }
        try body(list.unsafeMutablePointer)
    }
}
