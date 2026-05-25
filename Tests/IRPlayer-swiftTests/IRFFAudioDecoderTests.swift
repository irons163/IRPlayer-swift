import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFAudioDecoderTests: XCTestCase {

    func testAudioDataBufferRejectsMissingDecodedData() {
        XCTAssertNil(IRFFAudioDecoder.audioDataBuffer(fromDecodedData: nil))

        var byte: UInt8 = 0
        withUnsafeMutablePointer(to: &byte) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer)
            XCTAssertEqual(IRFFAudioDecoder.audioDataBuffer(fromDecodedData: pointer), rawPointer)
        }
    }

    func testAudioDataBufferRejectsMissingSwrBuffer() {
        XCTAssertNil(IRFFAudioDecoder.audioDataBuffer(fromSwrBuffer: nil))

        var byte: UInt8 = 0
        withUnsafeMutablePointer(to: &byte) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer)
            XCTAssertEqual(IRFFAudioDecoder.audioDataBuffer(fromSwrBuffer: rawPointer), rawPointer)
        }
    }

    func testInputChannelCapacityRejectsMissingOrInvalidCodecContext() {
        XCTAssertNil(IRFFAudioDecoder.inputChannelCapacity(from: nil))

        var codecContext = AVCodecContext()
        codecContext.channels = 0

        withUnsafeMutablePointer(to: &codecContext) { contextPointer in
            XCTAssertNil(IRFFAudioDecoder.inputChannelCapacity(from: contextPointer))

            contextPointer.pointee.channels = 2
            XCTAssertEqual(IRFFAudioDecoder.inputChannelCapacity(from: contextPointer), 2)
        }
    }

    func testSampleElementCountRejectsEmptyInputs() {
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 0, channelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 4, channelCount: 0))
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: -1, channelCount: 2))
        XCTAssertEqual(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 3, channelCount: 2), 6)
    }

    func testSampleElementCountRejectsOverflow() {
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: Int.max, channelCount: 2))
    }

    func testSampleByteCountRejectsInvalidAndOverflowingElementCounts() {
        XCTAssertNil(IRFFAudioDecoder.sampleByteCount(numberOfElements: 0))
        XCTAssertNil(IRFFAudioDecoder.sampleByteCount(numberOfElements: -1))
        XCTAssertNil(IRFFAudioDecoder.sampleByteCount(numberOfElements: Int.max))
    }

    func testSampleByteCountCalculatesFloatStorageSize() {
        XCTAssertEqual(IRFFAudioDecoder.sampleByteCount(numberOfElements: 3), 12)
    }

    func testFallbackDurationRejectsInvalidAudioOutputInfo() {
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 0, channelCount: 2, samplingRate: 48_000))
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 128, channelCount: 0, samplingRate: 48_000))
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 128, channelCount: 2, samplingRate: 0))
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 128, channelCount: 2, samplingRate: .infinity))
    }

    func testFallbackDurationCalculatesSecondsFromSampleBytes() throws {
        let duration = try XCTUnwrap(
            IRFFAudioDecoder.fallbackDuration(sampleByteCount: 384_000, channelCount: 2, samplingRate: 48_000)
        )

        XCTAssertEqual(duration, 1, accuracy: 0.0001)
    }

    func testResampleRatioRejectsInvalidAudioInfo() {
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 0, inputSamplingRate: 48_000, outputChannelCount: 2, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: .infinity, inputSamplingRate: 48_000, outputChannelCount: 2, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 0, outputChannelCount: 2, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 48_000, outputChannelCount: 0, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 48_000, outputChannelCount: 2, inputChannelCount: 0))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: Float64(Int.max), inputSamplingRate: 1, outputChannelCount: 2, inputChannelCount: 2))
    }

    func testResampleRatioClampsUpsamplingFactors() {
        XCTAssertEqual(
            IRFFAudioDecoder.resampleRatio(outputSamplingRate: 24_000, inputSamplingRate: 48_000, outputChannelCount: 1, inputChannelCount: 2),
            2
        )
        XCTAssertEqual(
            IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 24_000, outputChannelCount: 4, inputChannelCount: 2),
            8
        )
    }

    func testResampleRatioRoundsUpFractionalChannelExpansion() {
        XCTAssertEqual(
            IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 48_000, outputChannelCount: 3, inputChannelCount: 2),
            4
        )
    }

    func testResampleFrameCapacityRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: 0, ratio: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: 1024, ratio: 0))
        XCTAssertNil(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: Int32.max, ratio: 2))
    }

    func testResampleFrameCapacityCalculatesInt32Capacity() {
        XCTAssertEqual(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: 1024, ratio: 2), 2048)
    }
}

final class IRFFAudioFrameTests: XCTestCase {

    func testSampleCapacityRejectsInvalidByteLengths() {
        XCTAssertNil(IRFFAudioFrame.sampleCapacity(forByteLength: 0))
        XCTAssertNil(IRFFAudioFrame.sampleCapacity(forByteLength: -1))
    }

    func testSampleCapacityRoundsUpToFloatStorage() {
        XCTAssertEqual(IRFFAudioFrame.sampleCapacity(forByteLength: MemoryLayout<Float>.size), 1)
        XCTAssertEqual(IRFFAudioFrame.sampleCapacity(forByteLength: MemoryLayout<Float>.size + 1), 2)
    }
}
