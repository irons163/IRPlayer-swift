import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRGLViewSnapshotTests: XCTestCase {

    func testInitDoesNotPrintMetalSetupDebugOutput() {
        let output = captureStandardOutput {
            _ = IRGLView(frame: .zero)
        }

        XCTAssertEqual(output, "")
    }

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

    func testResetAllViewportConvertsFiniteDimensions() {
        let view = IRGLView(frame: .zero)

        view.resetAllViewport(w: 320.9, h: 180.2, resetTransform: false)

        XCTAssertEqual(view.viewprotRange, CGRect(x: 0, y: 0, width: 320, height: 180))
    }

    func testResetAllViewportIgnoresInvalidDimensions() {
        let view = IRGLView(frame: .zero)
        view.resetAllViewport(w: 320, h: 180, resetTransform: false)

        view.resetAllViewport(w: .infinity, h: 180, resetTransform: false)

        XCTAssertEqual(view.viewprotRange, CGRect(x: 0, y: 0, width: 320, height: 180))
    }

    func testDrawablePixelSizeRejectsInvalidDimensions() {
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: 0, height: 1)))
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: 1, height: CGFloat.nan)))
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: CGFloat.infinity, height: 1)))
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: CGFloat(Int.max) * 2, height: 1)))
    }

    func testDrawablePixelSizeConvertsFinitePositiveDimensions() {
        let size = IRGLView.drawablePixelSize(from: CGSize(width: 320.9, height: 180.2))

        XCTAssertEqual(size?.width, 320)
        XCTAssertEqual(size?.height, 180)
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

    func testFittedImageTransformCalculatesAspectFitScaleAndCentering() throws {
        let transform = try XCTUnwrap(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 400, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                          contentMode: .scaleAspectFit)
        )

        XCTAssertEqual(transform.scaleX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 0.25, accuracy: 0.0001)
        XCTAssertEqual(transform.translationX, 0, accuracy: 0.0001)
        XCTAssertEqual(transform.translationY, 25, accuracy: 0.0001)
    }

    func testFittedImageTransformCalculatesAspectFillScaleAndCentering() throws {
        let transform = try XCTUnwrap(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 400, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                          contentMode: .scaleAspectFill)
        )

        XCTAssertEqual(transform.scaleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.translationX, -50, accuracy: 0.0001)
        XCTAssertEqual(transform.translationY, 0, accuracy: 0.0001)
    }

    func testFittedImageTransformRejectsInvalidGeometry() {
        XCTAssertNil(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 0, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                          contentMode: .scaleAspectFit)
        )
        XCTAssertNil(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 400, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 100),
                                          contentMode: .scaleAspectFit)
        )
    }
}
