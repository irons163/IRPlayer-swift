//
//  IRGLProgram2DFisheye2Pano.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/23.
//

import Foundation

@objcMembers public class IRGLProgram2DFisheye2Pano: IRGLProgram2D {

    private var fish2Pano: IRGLFish2PanoShaderParams!
    private var willScrollX: Float = 0
    private var willScrollY: Float = 0

    override var contentMode: IRGLRenderContentMode {
        didSet {
            if self.contentMode != oldValue {
                updateTextureWidth(UInt(fish2Pano.textureWidth), height: UInt(fish2Pano.textureHeight))
            }
        }
    }

    override func vertexShader() -> String {
        return IRGLVertexShaderGLSL.getShardString()
    }

    override func fragmentShader() -> String {
        return IRGLFragmentFish2PanoShaderGLSL.getShaderString(pixelFormat: pixelFormat, antialias: Int(fish2Pano.antialias))
    }

//    override func setup(parameter: IRMediaParameter?) {
//        guard let parameter = parameter else { return }
//
//        if let fishParameter = parameter as? IRFisheyeParameter {
//            fish2Pano.fishcenterx = GLint(fishParameter.cx)
//            fish2Pano.fishcentery = GLint(fishParameter.cy)
//            fish2Pano.fishradiush = GLint(fishParameter.rx)
//            fish2Pano.fishradiusv = GLint(fishParameter.ry)
//        } else {
//            fish2Pano.fishcenterx = GLint(parameter.width / 2)
//            fish2Pano.fishcentery = GLint(parameter.height / 2)
//            fish2Pano.fishradiush = GLint(parameter.width / 2)
//            fish2Pano.fishradiusv = GLint(parameter.height / 2)
//        }
//    }

    override func initShaderParams() {
        fish2Pano = IRGLFish2PanoShaderParams()
        fish2Pano.delegate = self
    }

    override func updateTextureWidth(_ w: UInt, height h: UInt) {
        super.updateTextureWidth(w, height: h)
        fish2Pano.updateTextureWidth(w, height: h)
    }

    override func loadShaders() -> Bool {
        if super.loadShaders() {
            fish2Pano.resolveUniforms(program)
            return true
        }
        return false
    }

    override func setRenderFrame(_ frame: IRFFVideoFrame) {
        super.setRenderFrame(frame)

        if frame.width != fish2Pano.textureWidth || frame.height != fish2Pano.textureHeight {
            fish2Pano.updateTextureWidth(UInt(frame.width), height: UInt(frame.height))
        }
    }

    override func prepareRender() -> Bool {
        if super.prepareRender() {
            fish2Pano.prepareRender()
            return true
        }
        return false
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
}
