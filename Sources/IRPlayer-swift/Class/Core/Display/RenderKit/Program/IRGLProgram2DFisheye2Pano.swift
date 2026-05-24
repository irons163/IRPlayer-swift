//
//  IRGLProgram2DFisheye2Pano.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

@objcMembers public class IRGLProgram2DFisheye2Pano: IRGLProgram2D {

    private var fish2Pano: IRGLFish2PanoShaderParams?

    var metalFish2PanoParams: IRGLFish2PanoShaderParams? {
        return fish2Pano
    }
    private var willScrollX: Float = 0
    private var willScrollY: Float = 0

    override var contentMode: IRGLRenderContentMode {
        didSet {
            if self.contentMode != oldValue,
               let textureSize = Self.textureSize(from: fish2Pano) {
                updateTextureWidth(textureSize.width, height: textureSize.height)
            }
        }
    }

    override func initShaderParams() {
        fish2Pano = IRGLFish2PanoShaderParams()
        fish2Pano?.delegate = self
    }

    static func textureSize(from params: IRGLFish2PanoShaderParams?) -> (width: Int, height: Int)? {
        guard let params else { return nil }
        return (Int(params.textureWidth), Int(params.textureHeight))
    }

    static func normalizedOffsetX(currentOffset: Float, delta: Float, outputWidth: GLint) -> Float? {
        guard outputWidth > 0 else { return nil }

        let width = Float(outputWidth)
        var offset = currentOffset - delta
        while offset > width || offset < -width {
            if offset > width {
                offset -= width
            } else if offset < -width {
                offset += width
            }
        }
        return offset
    }

    override func updateTextureWidth(_ w: Int, height h: Int) {
        super.updateTextureWidth(w, height: h)
        fish2Pano?.updateTextureWidth(w, height: h)
    }

    override func setRenderFrame(_ frame: IRFFVideoFrame) {
        guard let fish2Pano else { return }
        if frame.width != fish2Pano.textureWidth || frame.height != fish2Pano.textureHeight {
            fish2Pano.updateTextureWidth(frame.width, height: frame.height)
        }
    }

    override public func willScroll(dx: Float, dy: Float, transformController: IRGLTransformController) {
        willScrollX = dx
        willScrollY = dy
    }

    override public func doScrollHorizontal(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxX) || status.contains(.toMinX) {
            guard let fish2Pano,
                  let transformController = tramsformController,
                  transformController.getScope().w != 0,
                  transformController.getScope().scaleX != 0 else {
                return false
            }
            let width = Float(fish2Pano.outputWidth) / Float(transformController.getScope().w)
            let delta = willScrollX / transformController.getScope().scaleX * width
            guard let offsetX = Self.normalizedOffsetX(
                currentOffset: fish2Pano.offsetX,
                delta: delta,
                outputWidth: fish2Pano.outputWidth
            ) else {
                return false
            }
            fish2Pano.offsetX = offsetX
            return false
        }
        return true
    }

    override func didDoubleTap() {
        super.didDoubleTap()
    }
}
