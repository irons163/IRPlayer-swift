//
//  SPMDemoUITests.swift
//  SPMDemoUITests
//
//  Created by irons on 2024/12/12.
//

import UIKit
import XCTest

final class SPMDemoUITests: XCTestCase {
    private enum FrameStorageExpectation: Equatable {
        case avPlayerLayer
        case coreVideoPixelBuffer
        case softwareYUV

        var accessibilityValue: String? {
            switch self {
            case .avPlayerLayer:
                return nil
            case .coreVideoPixelBuffer:
                return "frame-storage.cv-pixel-buffer"
            case .softwareYUV:
                return "frame-storage.software-yuv"
            }
        }
    }

    private struct FrameSample {
        let averageLuminance: Double
        let luma: [UInt8]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAVPlayerPlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "i see fire, AVPlayer",
            expectedFrameStorage: .avPlayerLayer
        )
    }

    @MainActor
    func testAVPlayerVRPlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "google help, AVPlayer, VR",
            expectedFrameStorage: .coreVideoPixelBuffer
        )
    }

    @MainActor
    func testAVPlayerVRBoxPlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "google help, AVPlayer, VR, Box",
            expectedFrameStorage: .coreVideoPixelBuffer
        )
    }

    @MainActor
    func testSoftwareFFmpegPlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "i see fire, FFmpeg",
            expectedFrameStorage: .softwareYUV
        )
    }

    @MainActor
    func testHardwareFFmpegPlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "i see fire, FFmpeg, Hardware Decode",
            expectedFrameStorage: .coreVideoPixelBuffer
        )
    }

    @MainActor
    func testFisheyePlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "fisheye-demo, FFmpeg, Fisheye Mode",
            expectedFrameStorage: .softwareYUV
        )
    }

    @MainActor
    func testPanoramaPlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "fisheye-demo, FFmpeg, Pano Mode",
            expectedFrameStorage: .softwareYUV
        )
    }

    @MainActor
    func testMultiModePlaybackDoesNotFlashBlack() throws {
        try assertPlaybackDoesNotFlashBlack(
            menuTitle: "fisheye-demo, FFmpeg, Multi Modes",
            expectedFrameStorage: .softwareYUV,
            selectedRenderMode: "Fourlens"
        )
    }

    @MainActor
    private func assertPlaybackDoesNotFlashBlack(
        menuTitle: String,
        expectedFrameStorage: FrameStorageExpectation,
        selectedRenderMode: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let app = XCUIApplication()
        app.launchEnvironment[
            "IRPLAYER_UI_TEST_LAYOUT_STRESS"
        ] = "1"
        app.launchEnvironment["IRPLAYER_UI_TEST_LONG_FISHEYE"] = "1"
        app.launch()

        let menuItem = app.staticTexts[menuTitle]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        menuItem.tap()

        let playingLabel = app.staticTexts["Playing"]
        XCTAssertTrue(
            playingLabel.waitForExistence(timeout: 15),
            file: file,
            line: line
        )
        let display = app.otherElements["player.display"]
        XCTAssertTrue(
            display.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        if let expectedValue =
                expectedFrameStorage.accessibilityValue {
            let storagePublished = XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "value == %@",
                    expectedValue
                ),
                object: display
            )
            let result = XCTWaiter.wait(
                for: [storagePublished],
                timeout: 10
            )
            XCTAssertEqual(
                result,
                .completed,
                "Expected \(expectedValue), got \(String(describing: display.value))",
                file: file,
                line: line
            )
        } else {
            XCTAssertFalse(
                (display.value as? String)?
                    .hasPrefix("frame-storage.") == true,
                "AVPlayerLayer unexpectedly submitted a decoded frame: \(String(describing: display.value))",
                file: file,
                line: line
            )
        }
        if let selectedRenderMode {
            try selectRenderMode(
                selectedRenderMode,
                in: app,
                file: file,
                line: line
            )
        }

        if menuTitle.hasPrefix("fisheye-demo") {
            let duration = app.staticTexts["player.duration"]
            let longFixtureLoaded = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "01:00"),
                object: duration
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [longFixtureLoaded], timeout: 5),
                .completed,
                "Expected the 60-second UI fixture before frame sampling",
                file: file,
                line: line
            )
        }

        // Skip initial attachment and sample the same bright portion of the
        // bundled fixture. A renderer regression that presents empty
        // drawables produces near-black samples between valid frames.
        Thread.sleep(forTimeInterval: 0.5)
        var samples: [FrameSample] = []
        for _ in 0..<24 {
            let screenshot = display.screenshot()
            let image = try XCTUnwrap(
                UIImage(data: screenshot.pngRepresentation),
                file: file,
                line: line
            )
            samples.append(
                try downsample(
                    of: image,
                    file: file,
                    line: line
                )
            )
            Thread.sleep(forTimeInterval: 0.08)
        }

        if menuTitle.hasPrefix("fisheye-demo") {
            XCTAssertFalse(
                app.staticTexts["Finished"].exists,
                "Fixture ended during sampling; final-frame retention is not a renderer freeze",
                file: file,
                line: line
            )
        }

        let luminances = samples.map(\.averageLuminance)
        let sorted = luminances.sorted()
        let median = sorted[sorted.count / 2]
        XCTAssertGreaterThan(
            median,
            0.02,
            "The sampled playback region never became visible: \(luminances)",
            file: file,
            line: line
        )
        let blackThreshold = min(0.012, median * 0.25)
        let blackSamples = luminances.filter { $0 < blackThreshold }
        XCTAssertTrue(
            blackSamples.isEmpty,
            "Playback flashed black between frames: \(luminances)",
            file: file,
            line: line
        )

        let adjacentChanges = zip(
            samples,
            samples.dropFirst()
        ).map(frameDifference)
        let changingPairCount = adjacentChanges.filter {
            $0 > 0.002
        }.count
        XCTAssertGreaterThanOrEqual(
            changingPairCount,
            3,
            "Playback stayed on a frozen non-black frame: \(adjacentChanges)",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            adjacentChanges.max() ?? 0,
            0.006,
            "Playback screenshots did not show meaningful temporal change: \(adjacentChanges)",
            file: file,
            line: line
        )

        let crossSampleChanges = (0..<(samples.count - 6)).map {
            frameDifference(samples[$0], samples[$0 + 6])
        }
        XCTAssertGreaterThan(
            crossSampleChanges.max() ?? 0,
            0.01,
            "Playback remained visually unchanged across the sampling window: \(crossSampleChanges)",
            file: file,
            line: line
        )
        if let expectedValue =
                expectedFrameStorage.accessibilityValue {
            XCTAssertEqual(
                display.value as? String,
                expectedValue,
                "Frame storage changed during playback: \(String(describing: display.value))",
                file: file,
                line: line
            )
        } else {
            XCTAssertFalse(
                (display.value as? String)?
                    .hasPrefix("frame-storage.") == true,
                "AVPlayerLayer switched to decoded-frame storage during playback: \(String(describing: display.value))",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func selectRenderMode(
        _ renderMode: String,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) throws {
        let modesButton =
            app.buttons["player.render-mode"]
        XCTAssertTrue(
            modesButton.waitForExistence(timeout: 5),
            "Render-mode selector did not appear",
            file: file,
            line: line
        )
        modesButton.tap()

        let modeAction = app.buttons[renderMode]
        XCTAssertTrue(
            modeAction.waitForExistence(timeout: 5),
            "Render mode \(renderMode) did not appear",
            file: file,
            line: line
        )
        modeAction.tap()

        let selectionPublished =
            XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "value == %@",
                    renderMode
                ),
                object: modesButton
            )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [selectionPublished],
                timeout: 5
            ),
            .completed,
            "Render mode selection was not applied; value=\(String(describing: modesButton.value))",
            file: file,
            line: line
        )

        // Restart after proving Fourlens was selected. The 60-second test
        // fixture leaves room for action-sheet, seek and screenshot latency;
        // the ordinary six-second demo fixture is not suitable for this test.
        let progressSlider =
            app.sliders["player.progress"]
        XCTAssertTrue(
            progressSlider.waitForExistence(timeout: 5),
            "Playback progress slider did not appear",
            file: file,
            line: line
        )
        progressSlider.adjust(
            toNormalizedSliderPosition: 0
        )
        let playButton = app.buttons["Play"]
        XCTAssertTrue(
            playButton.waitForExistence(timeout: 5),
            "Playback control did not appear",
            file: file,
            line: line
        )
        playButton.tap()
        XCTAssertTrue(
            app.staticTexts["Playing"]
                .waitForExistence(timeout: 5),
            "Playback did not resume after selecting \(renderMode)",
            file: file,
            line: line
        )
    }

    private func downsample(
        of image: UIImage,
        file: StaticString,
        line: UInt
    ) throws -> FrameSample {
        let cgImage = try XCTUnwrap(
            image.cgImage,
            file: file,
            line: line
        )
        let sourceBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )
        // Ignore the changing time label and controls around the edges so a
        // frozen video cannot pass the temporal-difference assertions.
        let playbackRect = CGRect(
            x: sourceBounds.width * 0.05,
            y: sourceBounds.height * 0.12,
            width: sourceBounds.width * 0.9,
            height: sourceBounds.height * 0.65
        ).integral
        let playbackImage = try XCTUnwrap(
            cgImage.cropping(
                to: playbackRect.intersection(sourceBounds)
            ),
            "Could not crop the central playback region",
            file: file,
            line: line
        )
        let width = 24
        let height = 24
        var pixels = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            file: file,
            line: line
        )
        context.interpolationQuality = .low
        context.draw(
            playbackImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var total = 0.0
        var luma = [UInt8]()
        luma.reserveCapacity(width * height)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let value = UInt8(
                (54 * red + 183 * green + 19 * blue) / 256
            )
            luma.append(value)
            total += Double(value) / 255
        }
        return FrameSample(
            averageLuminance:
                total / Double(width * height),
            luma: luma
        )
    }

    private func frameDifference(
        _ lhs: FrameSample,
        _ rhs: FrameSample
    ) -> Double {
        guard lhs.luma.count == rhs.luma.count,
              !lhs.luma.isEmpty else {
            return 0
        }
        var total = 0
        for (left, right) in zip(lhs.luma, rhs.luma) {
            total += abs(Int(left) - Int(right))
        }
        return Double(total)
            / Double(lhs.luma.count * 255)
    }
}
