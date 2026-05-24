//
//  IRFFTrackTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFTrackTests: XCTestCase {

    func testTrackBuilderClassifiesMediaStreamsAndKeepsMetadata() throws {
        let metadata = IRFFMetadata(dictionary: [
            "language": "jpn",
            "DURATION": "00:01:00.000"
        ])

        let videoTrack = try XCTUnwrap(IRFFFormatContext.track(index: 2, codecType: AVMEDIA_TYPE_VIDEO, metadata: metadata))
        XCTAssertEqual(videoTrack.index, 2)
        XCTAssertEqual(videoTrack.type, .video)
        XCTAssertTrue(videoTrack.metadata === metadata)

        let audioTrack = try XCTUnwrap(IRFFFormatContext.track(index: 3, codecType: AVMEDIA_TYPE_AUDIO, metadata: metadata))
        XCTAssertEqual(audioTrack.index, 3)
        XCTAssertEqual(audioTrack.type, .audio)
        XCTAssertTrue(audioTrack.metadata === metadata)
    }

    func testTrackBuilderIgnoresUnsupportedMediaStreams() {
        XCTAssertNil(IRFFFormatContext.track(index: 4, codecType: AVMEDIA_TYPE_SUBTITLE, metadata: nil))
        XCTAssertNil(IRFFFormatContext.track(index: 5, codecType: AVMEDIA_TYPE_UNKNOWN, metadata: nil))
    }
}
