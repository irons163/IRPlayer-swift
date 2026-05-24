//
//  IRPlayerDecoderTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRPlayerDecoderTests: XCTestCase {

    func testVideoFormatResolverClassifiesNilAsError() {
        XCTAssertEqual(IRVideoFormatResolver.format(for: nil), .error)
    }

    func testVideoFormatResolverClassifiesSchemesAndExtensionsCaseInsensitively() {
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "RTMP://example.com/live")), .rtmp)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "rtsp://example.com/live")), .rtsp)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "https://example.com/movie.MP4?token=1")), .mpeg4)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(string: "https://example.com/live.M3U8")), .m3u8)
        XCTAssertEqual(IRVideoFormatResolver.format(for: NSURL(fileURLWithPath: "/tmp/clip.flv")), .flv)
    }

    func testDecoderTypeUsesConfiguredPolicyForResolvedFormat() {
        let decoder = IRPlayerDecoder.FFmpegDecoder()
        decoder.mpeg4Format = .avPlayer

        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: NSURL(string: "https://example.com/video.mp4")), .avPlayer)
        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: NSURL(string: "https://example.com/video.unknown")), .ffmpeg)
        XCTAssertEqual(decoder.decoderTypeForContentURL(contentURL: nil), .error)
    }
}
