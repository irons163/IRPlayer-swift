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
}
