//
//  IRGLProgram2DFisheye2Persp.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

@objcMembers public class IRGLProgram2DFisheye2Persp: IRGLProgram2D {

    private var fish2Persp: IRGLFish2PerspShaderParams?
    private var willScrollX: Float = 0
    private var willScrollY: Float = 0
    private var transformXWhenTouchDown: Float = 0

    public func setTransform(x: Float, y: Float) {
        fish2Persp?.transformX = x
        fish2Persp?.transformY = y
    }

    override func initShaderParams() {
        fish2Persp = IRGLFish2PerspShaderParams()
        fish2Persp?.delegate = self
    }

    override func setRenderFrame(_ frame: IRFFVideoFrame) {
        if frame.width != (fish2Persp?.textureWidth ?? 0) || frame.height != (fish2Persp?.textureHeight ?? 0) {
            fish2Persp?.updateTextureWidth(frame.width, height: frame.height)
        }
    }

    override public func willScroll(dx: Float, dy: Float, transformController: IRGLTransformController) {
        willScrollX = dx
        willScrollY = dy
    }

    override public func doScrollHorizontal(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxX) || status.contains(.toMinX) {
            let moveDegree = -1 * (willScrollX * (180.0 / Float(fish2Persp!.outputWidth)))
            fish2Persp?.transformY -= moveDegree
            return false
        }
        return true
    }

    override public func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            fish2Persp?.transformX -= (willScrollY * (180.0 / (Float(fish2Persp!.fishradiush) * 2.0)))

            if fish2Persp!.transformX > 55 {
                fish2Persp!.transformX = 55
            } else if fish2Persp!.transformX < 0 {
                fish2Persp!.transformX = 0
            }
            return false
        }
        return true
    }
}
