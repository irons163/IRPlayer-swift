//
//  IRGLProgramMulti4P.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/23.
//

import Foundation

enum IRGLProgramMultiMode {
    case multiDisplay
    case singleDisplay
}

@objcMembers public class IRGLProgramMulti4P: IRGLProgramMulti {

    var touchedProgram: IRGLProgram2D?
    var displayMode: IRGLProgramMultiMode = .multiDisplay

    override public init(programs: [IRGLProgram2D], viewprotRange: CGRect) {
        super.init(programs: programs, viewprotRange: viewprotRange)
    }

    override func touchedInProgram(_ touchedPoint: CGPoint) -> Bool {
        var touchedInProgram = false
        touchedProgram = nil

        for program in programs {
            let touched = program.touchedInProgram(touchedPoint)
            if touched {
                touchedProgram = program
            }
            touchedInProgram = touchedInProgram || touched
        }
        return touchedInProgram
    }

    override func dispatchViewprotRange(_ viewprotRange: CGRect, resetTransform: Bool) {
        for i in 0..<programs.count {
            let program = programs[i]

            if displayMode == .multiDisplay {
                let viewportWidth = viewprotRange.size.width / 2.0
                let viewportHeight = viewprotRange.size.height / 2.0

                program.setViewportRange(CGRect(x: CGFloat(i % 2) * viewportWidth, y: CGFloat(i / 2) * viewportHeight, width: viewportWidth, height: viewportHeight), resetTransform: resetTransform)

            } else if displayMode == .singleDisplay {
                let viewportWidth = viewprotRange.size.width
                let viewportHeight = viewprotRange.size.height

                if program == touchedProgram {
                    program.setViewportRange(CGRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight), resetTransform: false)
                } else {
                    program.setViewportRange(CGRect(x: 0, y: 0, width: 0, height: 0), resetTransform: false)
                }
            }
        }
    }

    func setDefaultScale(scale: Float) {
        guard let program = touchedProgram else { return }
        program.setDefaultScale(scale)
    }

    override public func didPanByDegreeX(_ degreeX: Float, degreeY: Float) {
        guard let program = touchedProgram else { return }

        if displayMode == .singleDisplay {
            program.tramsformController?.scroll(byDegreeX: degreeX, degreey: degreeY)
        }
    }

    public override func didPanBydx(_ dx: Float, dy: Float) {
        guard let program = touchedProgram else { return }
        program.tramsformController?.scroll(byDx: dx, dy: dy)
    }

    override func didPinchByfx(_ fx: Float, fy: Float, dsx: Float, dsy: Float) {
        guard let program = touchedProgram else { return }
        let scaleX = (program.tramsformController?.getScope().scaleX ?? 1.0) * dsx
        let scaleY = (program.tramsformController?.getScope().scaleY ?? 1.0) * dsy

        program.didPinchByfx(fx - Float(program.viewprotRange.origin.x), fy: fy - Float(program.viewprotRange.origin.y), sx: scaleX, sy: scaleY)
    }

    override func didPinchByfx(_ fx: Float, fy: Float, sx: Float, sy: Float) {
        guard let program = touchedProgram else { return }
        program.didPinchByfx(fx - Float(program.viewprotRange.origin.x), fy: fy - Float(program.viewprotRange.origin.y), sx: sx, sy: sy)
    }

    override func didRotate(_ rotateRadians: Float) {
        guard let program = touchedProgram else { return }
        program.didRotate(rotateRadians)
    }

    override func didDoubleTap() {
        guard let program = touchedProgram else { return }

        if let doResetToDefaultScaleBlock = self.doResetToDefaultScaleBlock, doResetToDefaultScaleBlock(self) {
            program.didDoubleTap()
        } else if let transformController = program.tramsformController,
                  !CGPointEqualToPoint(CGPoint(x: CGFloat(transformController.getScope().scaleX), y: CGFloat(transformController.getScope().scaleY)), transformController.getDefaultTransformScale()) {
            program.didDoubleTap()
            return
        }

        let viewportWidth = self.viewprotRange.size.width
        let viewportHeight = self.viewprotRange.size.height

        if displayMode == .multiDisplay {
            displayMode = .singleDisplay
        } else if displayMode == .singleDisplay {
            displayMode = .multiDisplay
        }

        for i in 0..<programs.count {
            let program = programs[i]
            if displayMode == .multiDisplay {
                self.setViewportRange(self.viewprotRange, resetTransform: false)
            } else if displayMode == .singleDisplay {
                if program == touchedProgram {
                    program.setViewportRange(CGRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight), resetTransform: false)
                } else {
                    program.setViewportRange(CGRect(x: 0, y: 0, width: 0, height: 0), resetTransform: false)
                }
            }
        }
    }
}
