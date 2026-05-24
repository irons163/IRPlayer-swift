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
            fish2Pano.offsetX -= (willScrollX / transformController.getScope().scaleX * width)
            while Int32(fish2Pano.offsetX) > fish2Pano.outputWidth || fish2Pano.offsetX < -Float(fish2Pano.outputWidth) {
                if fish2Pano.offsetX > Float(fish2Pano.outputWidth) {
                    fish2Pano.offsetX -= Float(fish2Pano.outputWidth)
                } else if fish2Pano.offsetX < -Float(fish2Pano.outputWidth) {
                    fish2Pano.offsetX += Float(fish2Pano.outputWidth)
                }
            }
            return false
        }
        return true
    }

    override func didDoubleTap() {
        super.didDoubleTap()
    }
}
