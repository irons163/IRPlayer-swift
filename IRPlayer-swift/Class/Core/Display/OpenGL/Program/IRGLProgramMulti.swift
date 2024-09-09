//
//  IRGLProgramMulti.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/23.
//

import Foundation
import CoreGraphics
import GLKit

@objcMembers public class IRGLProgramMulti: IRGLProgram2D {
    
    var programs: [IRGLProgram2D]
    
    override var renderer: IRGLRender? {
        didSet {
            for program in programs {
                program.renderer = renderer
            }
        }
    }

    override var contentMode: IRGLRenderContentMode {
        didSet {
            for program in programs {
                program.contentMode = contentMode
            }
        }
    }

    init(programs: [IRGLProgram2D], viewprotRange: CGRect) {
        self.programs = programs
        super.init(pixelFormat: .RGB_IRPixelFormat, viewportRange: .zero, parameter: nil)
        self.setViewportRange(viewprotRange)
    }

    override func updateTextureWidth(_ w: UInt, height h: UInt) {
        super.updateTextureWidth(w, height: h)
        for program in programs {
            program.updateTextureWidth(w, height: h)
        }
    }

    override func loadShaders() -> Bool {
        var loadShadersSuccess = true
        for program in programs {
            loadShadersSuccess = loadShadersSuccess && program.loadShaders()
        }
        return loadShadersSuccess
    }

    override func touchedInProgram(_ touchedPoint: CGPoint) -> Bool {
        var touchedInProgram = false
        for program in programs {
            touchedInProgram = touchedInProgram || program.touchedInProgram(touchedPoint)
        }
        return touchedInProgram
    }

    override func setViewportRange(_ viewportRange: CGRect, resetTransform: Bool = true) {
        super.setViewportRange(viewportRange, resetTransform: resetTransform)
        dispatchViewprotRange(viewportRange, resetTransform: resetTransform)
    }

    func dispatchViewprotRange(_ viewprotRange: CGRect, resetTransform: Bool) {
        for program in programs {
            program.setViewportRange(viewprotRange, resetTransform: resetTransform)
        }
    }

    override func setRenderFrame(_ frame: IRFFVideoFrame?) {
        guard let frame = frame else { return }
        for program in programs {
            program.setRenderFrame(frame)
        }
    }

    override func setModelviewProj(_ modelviewProj: GLKMatrix4) {
        for program in programs {
            program.setModelviewProj(modelviewProj)
        }
    }

    override func prepareRender() -> Bool {
        var prepareRenderSuccess = true
        for program in programs {
            prepareRenderSuccess = prepareRenderSuccess && program.prepareRender()
        }
        return prepareRenderSuccess
    }

    override func render() {
        for program in programs {
            program.render()
        }
    }

    override func releaseProgram() {
        for program in programs {
            program.releaseProgram()
        }
    }

    override func getOutputSize() -> CGSize {
        return .zero
    }

    override func setDefaultScale(_ scale: Float) {
        for program in programs {
            program.setDefaultScale(scale)
        }
    }

    public override func didPanByDegreeX(_ degreeX: Float, degreeY: Float) {
        for program in programs {
            program.tramsformController?.scroll(degreeX: degreeX, degreeY: degreeY)
        }
    }

    public override func didPanBydx(_ dx: Float, dy: Float) {
        for program in programs {
            program.tramsformController?.scroll(dx: dx, dy: dy)
        }
    }

    override func didPinchByfx(_ fx: Float, fy: Float, dsx: Float, dsy: Float) {
        for program in programs {
            let scaleX = (program.tramsformController?.getScope().scaleX ?? 1.0) * dsx
            let scaleY = (program.tramsformController?.getScope().scaleY ?? 1.0) * dsy
            program.didPinchByfx(fx, fy: fy, sx: scaleX, sy: scaleY)
        }
    }

    override func didPinchByfx(_ fx: Float, fy: Float, sx: Float, sy: Float) {
        for program in programs {
            program.didPinchByfx(fx, fy: fy, sx: sx, sy: sy)
        }
    }

    override func didRotate(_ rotateRadians: Float) {
        for program in programs {
            program.didRotate(rotateRadians)
        }
    }

    override func didDoubleTap() {
        for program in programs {
            program.didDoubleTap()
        }
    }

    override var doResetToDefaultScaleBlock: IRGLProgram2DResetScaleBlock? {
        didSet {
            for program in programs {
                program.doResetToDefaultScaleBlock = doResetToDefaultScaleBlock
            }
        }
    }
}
