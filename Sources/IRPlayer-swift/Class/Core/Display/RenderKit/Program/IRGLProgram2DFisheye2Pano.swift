//
//  IRGLProgram2DFisheye2Pano.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

@objcMembers public class IRGLProgram2DFisheye2Pano: IRGLProgram2D {

    private var fish2Pano: IRGLFish2PanoShaderParams!

    var metalFish2PanoParams: IRGLFish2PanoShaderParams? {
        return fish2Pano
    }
    private var willScrollX: Float = 0
    private var willScrollY: Float = 0

    override var contentMode: IRGLRenderContentMode {
        didSet {
            if self.contentMode != oldValue {
                updateTextureWidth(Int(fish2Pano.textureWidth), height: Int(fish2Pano.textureHeight))
            }
        }
    }

    override func initShaderParams() {
        fish2Pano = IRGLFish2PanoShaderParams()
        fish2Pano.delegate = self
    }

    override func updateTextureWidth(_ w: Int, height h: Int) {
        super.updateTextureWidth(w, height: h)
        fish2Pano.updateTextureWidth(w, height: h)
    }

    override func setRenderFrame(_ frame: IRFFVideoFrame) {
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
            guard let transformController = tramsformController,
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
