//
//  IRGLProgramMulti.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import CoreGraphics

@objcMembers public class IRGLProgramMulti: IRGLProgram2D {

    var programs: [IRGLProgram2D]

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

    override func updateTextureWidth(_ w: Int, height h: Int) {
        super.updateTextureWidth(w, height: h)
        for program in programs {
            program.updateTextureWidth(w, height: h)
        }
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

    override func setRenderFrame(_ frame: IRFFVideoFrame) {
        for program in programs {
            program.setRenderFrame(frame)
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

    override func didDoubleTap() {
        for program in programs {
            program.didDoubleTap()
        }
    }
}
