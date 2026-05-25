import CoreMedia
import Foundation
import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFVideoToolBoxTests: XCTestCase {

    func testThreeByteNALPayloadValidationRejectsTruncatedUnits() throws {
        try assertThreeByteNALPayload([0, 0, 1, 42], isValid: true)
        try assertThreeByteNALPayload([0, 0], isValid: false)
        try assertThreeByteNALPayload([0, 0, 5, 1, 2], isValid: false)
    }

    func testPacketPayloadRejectsMissingOrEmptyPacketData() {
        var packet = AVPacket()
        packet.size = 4
        XCTAssertNil(IRFFVideoToolBox.packetPayload(for: packet))

        var bytes = [UInt8](arrayLiteral: 1, 2, 3, 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            packet.data = buffer.baseAddress
            packet.size = 0
            XCTAssertNil(IRFFVideoToolBox.packetPayload(for: packet))

            packet.size = Int32(buffer.count)
            let payload = IRFFVideoToolBox.packetPayload(for: packet)
            XCTAssertEqual(payload?.data, buffer.baseAddress)
            XCTAssertEqual(payload?.size, Int32(buffer.count))
        }
    }

    func testConvertedNALBlockPayloadRejectsMissingOrInvalidBuffer() {
        XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: nil, demuxSize: 4, packetSize: 4))

        var bytes = [UInt8](arrayLiteral: 1, 2, 3, 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            let pointer = buffer.baseAddress

            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 0, packetSize: 4))
            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 4, packetSize: 0))
            XCTAssertNil(IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 4, packetSize: 5))

            let payload = IRFFVideoToolBox.convertedNALBlockPayload(memoryBlock: pointer, demuxSize: 5, packetSize: 4)
            XCTAssertEqual(payload?.memoryBlock, pointer)
            XCTAssertEqual(payload?.blockLength, 5)
            XCTAssertEqual(payload?.dataLength, 4)
        }
    }

    private func assertThreeByteNALPayload(_ bytes: [UInt8], isValid: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        var packet = AVPacket()
        var bytes = bytes

        let isBounded = try bytes.withUnsafeMutableBufferPointer { buffer in
            let data = try XCTUnwrap(buffer.baseAddress)
            packet.data = data
            packet.size = Int32(buffer.count)
            let payload = try XCTUnwrap(IRFFVideoToolBox.packetPayload(for: packet))
            return IRFFVideoToolBox.threeByteNALUnitsAreBounded(in: payload)
        }

        XCTAssertEqual(isBounded, isValid, file: file, line: line)
    }

    func testOutputCallbackIgnoresMissingRefConAndUpdatesDecoderState() {
        IRFFVideoToolBox.handleOutputCallback(refCon: nil, status: -1, imageBuffer: nil)

        var codecContext = AVCodecContext()
        withUnsafeMutablePointer(to: &codecContext) { context in
            let videoToolBox = IRFFVideoToolBox.videoToolBox(with: context)
            let refCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(videoToolBox).toOpaque())

            IRFFVideoToolBox.handleOutputCallback(refCon: refCon, status: -2, imageBuffer: nil)

            XCTAssertEqual(videoToolBox.decodeStatus, -2)
            XCTAssertNil(videoToolBox.decodeOutput)
        }
    }

    func testFormatDescriptionExtensionsIncludeExpectedAVCCAtom() throws {
        let extradata = [UInt8](arrayLiteral: 1, 2, 3, 4)

        let extensions: NSDictionary = try extradata.withUnsafeBufferPointer { buffer in
            let pointer = try XCTUnwrap(buffer.baseAddress)
            return IRFFVideoToolBox.makeFormatDescriptionExtensions(extradata: pointer, extradataSize: Int32(buffer.count)) as NSDictionary
        }

        let atoms = try XCTUnwrap(extensions["SampleDescriptionExtensionAtoms"] as? NSDictionary)
        let avcC = try XCTUnwrap(atoms["avcC"] as? Data)
        XCTAssertEqual(Array(avcC), extradata)
        XCTAssertEqual(extensions["CVImageBufferChromaLocationBottomField"] as? String, "left")
        XCTAssertEqual(extensions["CVImageBufferChromaLocationTopField"] as? String, "left")
        XCTAssertEqual(extensions["FullRangeVideo"] as? Bool, false)
    }

    func testRequiredFormatDescriptionRejectsMissingDescription() throws {
        XCTAssertNil(IRFFVideoToolBox.requiredFormatDescription(nil))

        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: kCMVideoCodecType_H264,
            width: 16,
            height: 8,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        XCTAssertEqual(status, noErr)
        let payload = try XCTUnwrap(IRFFVideoToolBox.requiredFormatDescription(formatDescription))
        let dimensions = CMVideoFormatDescriptionGetDimensions(payload)
        XCTAssertEqual(dimensions.width, 16)
        XCTAssertEqual(dimensions.height, 8)
    }

    func testDecodeFramePayloadRejectsMissingInputs() {
        XCTAssertNil(IRFFVideoToolBox.decodeFramePayload(session: nil, sampleBuffer: nil))
    }
}
