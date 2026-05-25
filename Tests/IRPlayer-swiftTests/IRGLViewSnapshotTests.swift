import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRGLViewSnapshotTests: XCTestCase {

    func testCreateImageFromFramebufferReturnsImageForZeroSizedView() {
        let view = IRGLView(frame: .zero)

        let image = view.createImageFromFramebuffer()

        XCTAssertEqual(image.size, .zero)
    }

    func testRenderModeSelectionRequiresRegisteredMode() {
        let view = IRGLView(frame: .zero)
        let firstMode = IRGLRenderMode2D()
        let secondMode = IRGLRenderMode2D()
        let externalMode = IRGLRenderMode2D()

        view.setRenderModes([firstMode, secondMode])

        XCTAssertEqual(view.getRenderModes().count, 2)
        XCTAssertTrue(view.getCurrentRenderMode() === firstMode)
        XCTAssertFalse(view.choose(renderMode: nil, withImmediatelyRenderOnce: false))
        XCTAssertFalse(view.choose(renderMode: externalMode, withImmediatelyRenderOnce: false))

        XCTAssertTrue(view.choose(renderMode: secondMode, withImmediatelyRenderOnce: false))
        XCTAssertTrue(view.getCurrentRenderMode() === secondMode)
        XCTAssertTrue(secondMode.program != nil)
    }

    func testTexUVTextureLayoutRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRGLView.texUVTextureLayout(width: 0, height: 1))
        XCTAssertNil(IRGLView.texUVTextureLayout(width: 1, height: 0))
        XCTAssertNil(IRGLView.texUVTextureLayout(width: Int.max, height: 2))
    }

    func testTexUVTextureLayoutCalculatesRGFloatRows() {
        let layout = IRGLView.texUVTextureLayout(width: 3, height: 2)

        XCTAssertEqual(layout?.bytesPerRow, 24)
        XCTAssertEqual(layout?.totalByteCount, 48)
    }
}
