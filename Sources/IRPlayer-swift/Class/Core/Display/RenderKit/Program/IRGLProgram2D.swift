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

@objc public enum IRGLRenderContentMode: Int {
    case scaleAspectFit
    case scaleAspectFill
    case scaleToFill
}

typealias IRGLProgram2DResetScaleBlock = (_ program: IRGLProgram2D) -> Bool

@objcMembers public class IRGLProgram2D: NSObject, IRGLTransformControllerDelegate {

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

    static func viewportSize(from viewportRange: CGRect) -> (width: Int, height: Int)? {
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
        return (Int(width), Int(height))
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
        if frame.width != (shaderParams2D?.textureWidth ?? 0) || frame.height != (shaderParams2D?.textureHeight ?? 0) {
            updateTextureWidth(frame.width, height: frame.height)
        }
    }

    func updateTextureWidth(_ width: Int, height: Int) {
        shaderParams2D?.updateTextureWidth(width, height: height)
    }

    func calculateViewport() -> CGRect {
        guard let transformController = transformController else { return .zero }
        let vw = Float(transformController.getScope().w)
        let vh = Float(transformController.getScope().h)

        let w = vw * transformController.getScope().scaleX
        let newX = (-1 * (vw - w)) / 2
        let viewportX = transformController.getScope().scaleX < 1.0 ? newX : 0
        let newY = -1 * (vh - vh * transformController.getScope().scaleY) / 2
        let viewportY = transformController.getScope().scaleY < 1.0 ? newY : 0

        return CGRect(x: viewprotRange.origin.x + CGFloat(viewportX),
                      y: viewprotRange.origin.y + CGFloat(viewportY),
                      width: viewprotRange.width,
                      height: viewprotRange.height)
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
        var didScrollToBoundsHorizontal = false
        var didScrollToBoundsVertical = false
        var scrollToBounds: IRGLTransformController.ScrollToBounds = .none

        if status.contains(.toMaxX) || status.contains(.toMinX) {
            didScrollToBoundsHorizontal = true
            scrollToBounds = .horizontal
        }
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            didScrollToBoundsVertical = true
            scrollToBounds = .vertical
        }

        if didScrollToBoundsHorizontal && didScrollToBoundsVertical {
            scrollToBounds = .both
        }

        if let delegate = delegate, scrollToBounds != .none {
            delegate.didScrollToBounds(scrollToBounds, withProgram: self)
        }
    }
}

extension IRGLProgram2D: IRGLShaderParamsDelegate {

    public func didUpdateOutputWH(_ w: Int, _ h: Int) {
        if let transformController = transformController {
            let width = Double(w)
            let height = Double(h)
            let viewportWidth = Double(transformController.getScope().w)
            let viewportHeight = Double(transformController.getScope().h)
            guard width > 0, height > 0, viewportWidth > 0, viewportHeight > 0 else { return }
            let dH = viewportHeight / height
            let dW = viewportWidth / width
            var dd: Double

            switch contentMode {
            case .scaleAspectFit:
                dd = min(dH, dW)
            case .scaleAspectFill:
                dd = max(dH, dW)
            case .scaleToFill:
                dd = 0
            @unknown default:
                dd = 0
            }

            if dd > 0 {
                let sy = height * dd / viewportHeight
                let sx = width * dd / viewportWidth

                transformController.setupDefaultTransform(scaleX: Float(sx), scaleY: Float(sy))

                if (dH != 1 || dW != 1) && shouldUpdateToDefaultWhenOutputSizeChanged {
                    transformController.updateToDefault()
                }
            }
        }
    }
}
