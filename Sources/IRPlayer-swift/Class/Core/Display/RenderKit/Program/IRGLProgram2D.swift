//
//  IRGLProgram2D.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import UIKit

protocol IRGLProgramDelegate: AnyObject {
    func didScrollToBounds(_ bounds: IRGLTransformController.ScrollToBounds, withProgram program: IRGLProgram2D)
}

@objc public enum IRGLRenderContentMode: Int, Hashable, Equatable, Sendable, RawRepresentable {
    case scaleAspectFit
    case scaleAspectFill
    case scaleToFill
}

typealias IRGLProgram2DResetScaleBlock = (_ program: IRGLProgram2D) -> Bool

@objcMembers public class IRGLProgram2D: NSObject, IRGLTransformControllerDelegate {

    struct ViewportSize: Equatable {
        let width: Int
        let height: Int
    }

    struct OutputScaleDecision: Equatable {
        let scaleX: Float
        let scaleY: Float
        let shouldUpdateToDefault: Bool
    }

    var pixelFormat: IRPixelFormat
    var shaderParams2D: IRGLShaderParams?

    var parameter: IRMediaParameter?
    var transformController: IRGLTransformController?
    var doResetToDefaultScaleBlock: IRGLProgram2DResetScaleBlock?
    var mapProjection: IRGLProjection?
    weak var delegate: IRGLProgramDelegate?
    var contentMode: IRGLRenderContentMode = .scaleAspectFit {
        didSet {
            if self.contentMode != oldValue {
                updateTextureWidth(Int(shaderParams2D?.textureWidth ?? 0), height: Int(shaderParams2D?.textureHeight ?? 0))
            }
        }
    }
    var viewprotRange: CGRect = .zero
    var shouldUpdateToDefaultWhenOutputSizeChanged: Bool = true

    override convenience init() {
        self.init(pixelFormat: .RGB_IRPixelFormat, viewportRange: .zero, parameter: nil)
    }

    public init(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) {
        self.pixelFormat = pixelFormat
        super.init()
        initShaderParams()
        setViewportRange(viewportRange)
        self.parameter = parameter
        self.shouldUpdateToDefaultWhenOutputSizeChanged = true
    }

    static func viewportSize(from viewportRange: CGRect) -> ViewportSize? {
        let width = viewportRange.width
        let height = viewportRange.height
        guard width.isFinite,
              height.isFinite,
              width >= 0,
              height >= 0,
              width <= CGFloat(Int.max),
              height <= CGFloat(Int.max) else {
            return nil
        }
        return ViewportSize(
            width: Int(width),
            height: Int(height)
        )
    }

    static func scrollToBounds(for status: IRGLTransformController.ScrollStatus) -> IRGLTransformController.ScrollToBounds {
        let reachedHorizontal =
            status.contains(.toMaxX) ||
            status.contains(.toMinX)
        let reachedVertical =
            status.contains(.toMaxY) ||
            status.contains(.toMinY)
        switch (reachedHorizontal, reachedVertical) {
        case (true, true):
            return .both
        case (true, false):
            return .horizontal
        case (false, true):
            return .vertical
        case (false, false):
            return .none
        }
    }

    static func outputScaleDecision(
        outputWidth: Int,
        outputHeight: Int,
        viewportWidth: Int,
        viewportHeight: Int,
        contentMode: IRGLRenderContentMode,
        shouldUpdateToDefaultWhenOutputSizeChanged: Bool
    ) -> OutputScaleDecision? {
        guard outputWidth > 0,
              outputHeight > 0,
              viewportWidth > 0,
              viewportHeight > 0 else {
            return nil
        }

        let width = Double(outputWidth)
        let height = Double(outputHeight)
        let viewportWidth = Double(viewportWidth)
        let viewportHeight = Double(viewportHeight)
        let heightRatio = viewportHeight / height
        let widthRatio = viewportWidth / width
        guard heightRatio.isFinite,
              widthRatio.isFinite,
              heightRatio > 0,
              widthRatio > 0 else {
            return nil
        }

        let scaleRatio: Double
        switch contentMode {
        case .scaleAspectFit:
            scaleRatio = min(heightRatio, widthRatio)
        case .scaleAspectFill:
            scaleRatio = max(heightRatio, widthRatio)
        case .scaleToFill:
            return nil
        @unknown default:
            return nil
        }
        guard scaleRatio.isFinite, scaleRatio > 0 else {
            return nil
        }

        let scaleXValue =
            width * scaleRatio / viewportWidth
        let scaleYValue =
            height * scaleRatio / viewportHeight
        guard scaleXValue.isFinite,
              scaleYValue.isFinite,
              scaleXValue > 0,
              scaleYValue > 0,
              scaleXValue <= Double(Float.greatestFiniteMagnitude),
              scaleYValue <= Double(Float.greatestFiniteMagnitude) else {
            return nil
        }

        let scaleX = Float(scaleXValue)
        let scaleY = Float(scaleYValue)
        guard scaleX.isFinite,
              scaleY.isFinite,
              scaleX > 0,
              scaleY > 0 else {
            return nil
        }

        return OutputScaleDecision(
            scaleX: scaleX,
            scaleY: scaleY,
            shouldUpdateToDefault:
                (heightRatio != 1 || widthRatio != 1) &&
                shouldUpdateToDefaultWhenOutputSizeChanged
        )
    }

    func initShaderParams() {
        shaderParams2D = IRGLShaderParams()
        shaderParams2D?.delegate = self
    }

    func setViewportRange(_ viewportRange: CGRect, resetTransform: Bool = true) {
        self.viewprotRange = viewportRange
        guard let viewportSize = Self.viewportSize(from: viewportRange) else { return }
        transformController?.resetViewport(width: viewportSize.width, height: viewportSize.height, resetTransform: resetTransform)
    }

    func setDefaultScale(_ scale: Float) {
        if let oldScaleRange = transformController?.scaleRange {
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange.minScaleX, minScaleY: oldScaleRange.minScaleY, maxScaleX: oldScaleRange.maxScaleX, maxScaleY: oldScaleRange.maxScaleY, defaultScaleX: scale, defaultScaleY: scale)
            transformController?.scaleRange = newScaleRange
        }
    }

    func getCurrentScale() -> CGPoint {
        guard let transformController = transformController else { return .zero }
        let defaultScale = transformController.getDefaultTransformScale()
        let scope = transformController.getScope()
        return CGPoint(x: defaultScale.x == 0 ? 0 : CGFloat(scope.scaleX) / defaultScale.x,
                       y: defaultScale.y == 0 ? 0 : CGFloat(scope.scaleY) / defaultScale.y)
    }

    public var tramsformController: IRGLTransformController? {
        get { transformController }
        set { transformController = newValue }
    }

    func touchedInProgram(_ touchedPoint: CGPoint) -> Bool {
        return viewprotRange.contains(touchedPoint)
    }

    func getOutputSize() -> CGSize {
        return CGSize(width: CGFloat(shaderParams2D?.outputWidth ?? 0), height: CGFloat(shaderParams2D?.outputHeight ?? 0))
    }

    func setRenderFrame(_ frame: IRFFVideoFrame) {
        let dimensions = frame.dimensionSnapshot()
        if dimensions.width !=
            (shaderParams2D?.textureWidth ?? 0)
            || dimensions.height !=
            (shaderParams2D?.textureHeight ?? 0) {
            updateTextureWidth(
                dimensions.width,
                height: dimensions.height
            )
        }
    }

    func updateTextureWidth(_ width: Int, height: Int) {
        shaderParams2D?.updateTextureWidth(width, height: height)
    }

    func calculateViewport() -> CGRect {
        guard let transformController = transformController else { return .zero }
        let scope = transformController.getScope()
        let vw = Float(scope.w)
        let vh = Float(scope.h)
        guard vw.isFinite,
              vh.isFinite,
              vw >= 0,
              vh >= 0,
              scope.scaleX.isFinite,
              scope.scaleY.isFinite,
              scope.scaleX > 0,
              scope.scaleY > 0,
              viewprotRange.origin.x.isFinite,
              viewprotRange.origin.y.isFinite,
              viewprotRange.width.isFinite,
              viewprotRange.height.isFinite,
              viewprotRange.width >= 0,
              viewprotRange.height >= 0 else {
            return .zero
        }

        let scaledWidth = vw * scope.scaleX
        let scaledHeight = vh * scope.scaleY
        guard scaledWidth.isFinite,
              scaledHeight.isFinite else {
            return .zero
        }

        let viewportX =
            scope.scaleX < 1
            ? -(vw - scaledWidth) / 2
            : 0
        let viewportY =
            scope.scaleY < 1
            ? -(vh - scaledHeight) / 2
            : 0
        guard viewportX.isFinite,
              viewportY.isFinite else {
            return .zero
        }

        let x = viewprotRange.origin.x + CGFloat(viewportX)
        let y = viewprotRange.origin.y + CGFloat(viewportY)
        guard x.isFinite, y.isFinite else { return .zero }
        return CGRect(
            x: x,
            y: y,
            width: viewprotRange.width,
            height: viewprotRange.height
        )
    }

    public func didPanBydx(_ dx: Float, dy: Float) {
        transformController?.scroll(dx: dx, dy: dy)
    }

    func didPinchByfx(_ fx: Float, fy: Float, sx: Float, sy: Float) {
        guard let scale = transformController?.getScope() else { return }
        transformController?.update(fx: (Float(scale.w) - (fx * Float(UIScreen.main.scale))), fy: fy * Float(UIScreen.main.scale), sx: sx, sy: sy)
    }

    func didPinchByfx(_ fx: Float, fy: Float, dsx: Float, dsy: Float) {
        guard let scale = transformController?.getScope() else { return }
        let scaleX = scale.scaleX * dsx
        let scaleY = scale.scaleY * dsy

        didPinchByfx(fx, fy: fy, sx: scaleX, sy: scaleY)
    }

    public func didPanByDegreeX(_ degreeX: Float, degreeY: Float) {
        transformController?.scroll(degreeX: degreeX, degreeY: degreeY)
    }

    func didRotate(_ rotateRadians: Float) {
        transformController?.rotate(degree: rotateRadians * 180 / .pi)
    }

    func didDoubleTap() {
        if let doResetToDefaultScaleBlock = doResetToDefaultScaleBlock, doResetToDefaultScaleBlock(self) {
            return
        }
        transformController?.updateToDefault()
    }

    public func willScroll(dx: Float, dy: Float, transformController: IRGLTransformController) {
        // No implementation needed
    }

    public func doScrollHorizontal(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        return true
    }

    public func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        return true
    }

    public func didScroll(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) {
        let scrollToBounds = Self.scrollToBounds(for: status)

        if let delegate = delegate, scrollToBounds != .none {
            delegate.didScrollToBounds(scrollToBounds, withProgram: self)
        }
    }
}

extension IRGLProgram2D: IRGLShaderParamsDelegate {

    public func didUpdateOutputWH(_ w: Int, _ h: Int) {
        if let transformController = transformController {
            guard let decision = Self.outputScaleDecision(
                outputWidth: w,
                outputHeight: h,
                viewportWidth: transformController.getScope().w,
                viewportHeight: transformController.getScope().h,
                contentMode: contentMode,
                shouldUpdateToDefaultWhenOutputSizeChanged: shouldUpdateToDefaultWhenOutputSizeChanged
            ) else {
                return
            }

            transformController.setupDefaultTransform(scaleX: decision.scaleX, scaleY: decision.scaleY)

            if decision.shouldUpdateToDefault {
                transformController.updateToDefault()
            }
        }
    }
}
