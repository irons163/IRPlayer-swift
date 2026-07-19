import XCTest
@testable import IRPlayer_swift

final class IRPlayerRenderConfigurationTests: XCTestCase {
    func testNormalConfigurationUsesNormalModesAndGestures() {
        let configuration = IRPlayerRenderConfiguration.make(videoType: .normal, displayMode: .normal)

        XCTAssertFalse(configuration.modes?.isEmpty ?? true)
        XCTAssertNil(configuration.gravityMode)
        XCTAssertEqual(configuration.interaction, .gestures)
    }

    func testVRConfigurationSelectsInteractionFromDisplayMode() throws {
        let normal = IRPlayerRenderConfiguration.make(videoType: .vr, displayMode: .normal)
        let box = IRPlayerRenderConfiguration.make(videoType: .vr, displayMode: .box)

        XCTAssertTrue(try XCTUnwrap(normal.modes?.first) is IRGLRenderModeVR)
        XCTAssertEqual(normal.interaction, .gestures)
        XCTAssertTrue(try XCTUnwrap(box.modes?.first) is IRGLRenderModeDistortion)
        XCTAssertEqual(box.interaction, .motion)
        XCTAssertEqual(box.gravityMode, .resizeAspect)
        XCTAssertEqual(box.modes?.first?.defaultScale, 1.5)
        XCTAssertEqual(box.modes?.first?.aspect, 16.0 / 9.0)
    }

    func testFisheyeAndPanoramaBuildTheirDedicatedModes() throws {
        let fisheye = IRPlayerRenderConfiguration.make(videoType: .fisheye, displayMode: .normal)
        let panorama = IRPlayerRenderConfiguration.make(videoType: .pano, displayMode: .normal)

        XCTAssertTrue(try XCTUnwrap(fisheye.modes?.first) is IRGLRenderMode3DFisheye)
        XCTAssertTrue(try XCTUnwrap(panorama.modes?.first) is IRGLRenderMode2DFisheye2Pano)
        XCTAssertEqual(fisheye.gravityMode, .resizeAspect)
    }

    func testCustomConfigurationPreservesCallerSuppliedModes() {
        let configuration = IRPlayerRenderConfiguration.make(videoType: .custom, displayMode: .box)

        XCTAssertNil(configuration.modes)
        XCTAssertNil(configuration.gravityMode)
        XCTAssertEqual(configuration.interaction, .gestures)
    }
}
