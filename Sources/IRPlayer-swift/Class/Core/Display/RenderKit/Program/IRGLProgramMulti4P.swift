//
//  IRGLProgramMulti4P.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/23.
//

import Foundation
import CoreGraphics

enum IRGLProgramMultiMode {
    case multiDisplay
    case singleDisplay
}

@objcMembers public class IRGLProgramMulti4P: IRGLProgramMulti {

    var touchedProgram: IRGLProgram2D?
    var displayMode: IRGLProgramMultiMode = .multiDisplay

    static func viewportRanges(
        in viewprotRange: CGRect,
        displayMode: IRGLProgramMultiMode,
        programCount: Int,
        selectedIndex: Int?
    ) -> [CGRect] {
        return IRGLProgramMulti4PPolicy.viewportRanges(
            in: viewprotRange,
            displayMode: displayMode,
            programCount: programCount,
            selectedIndex: selectedIndex
        )
    }

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
        let selectedIndex = touchedProgram.flatMap { selectedProgram in
            programs.firstIndex { $0 === selectedProgram }
        }
        let ranges = Self.viewportRanges(
            in: viewprotRange,
            displayMode: displayMode,
            programCount: programs.count,
            selectedIndex: selectedIndex
        )
        let shouldResetTransform = displayMode == .multiDisplay ? resetTransform : false

        for (program, range) in zip(programs, ranges) {
            program.setViewportRange(range, resetTransform: shouldResetTransform)
        }
    }

    override func setDefaultScale(_ scale: Float) {
        guard let program = touchedProgram else { return }
        program.setDefaultScale(scale)
    }

    override func getCurrentScale() -> CGPoint {
        guard let program = touchedProgram else { return .zero }
        return program.getCurrentScale()
    }

    override public func didPanByDegreeX(_ degreeX: Float, degreeY: Float) {
        guard let program = touchedProgram else { return }

        if displayMode == .singleDisplay {
            program.tramsformController?.scroll(degreeX: degreeX, degreeY: degreeY)
        }
    }

    public override func didPanBydx(_ dx: Float, dy: Float) {
        guard let program = touchedProgram else { return }
        program.tramsformController?.scroll(dx: dx, dy: dy)
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
            return
        } else if let transformController = program.tramsformController,
                  !CGPointEqualToPoint(CGPoint(x: CGFloat(transformController.getScope().scaleX), y: CGFloat(transformController.getScope().scaleY)), transformController.getDefaultTransformScale()) {
            program.didDoubleTap()
            return
        }

        if displayMode == .multiDisplay {
            displayMode = .singleDisplay
        } else if displayMode == .singleDisplay {
            displayMode = .multiDisplay
        }

        dispatchViewprotRange(self.viewprotRange, resetTransform: false)
    }
}
