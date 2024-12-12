//
//  IRePTZShiftController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/21.
//

import Foundation

public class IRePTZShiftController {
    public var enabled: Bool
    public var panAngle: Float
    public var tiltAngle: Float
    public var panFactor: Float
    public var tiltFactor: Float
    var program: IRGLProgram2D?

    init() {
        self.enabled = true
        self.panAngle = 0
        self.tiltAngle = 0
        self.panFactor = 1.0
        self.tiltFactor = 1.0
    }

    func shiftDegreeX(_ degreeX: Float, degreeY: Float) {
        guard enabled else { return }

        var adjustedDegreeX = degreeX
        var adjustedDegreeY = degreeY

        if panAngle == 0 {
            adjustedDegreeX = 0
        } else {
            adjustedDegreeX = degreeX * panFactor * 360 / panAngle
        }

        if tiltAngle == 0 {
            adjustedDegreeY = 0
        } else {
            adjustedDegreeY = degreeY * tiltFactor * 360 / tiltAngle
        }

        program?.didPanByDegreeX(adjustedDegreeX, degreeY: adjustedDegreeY)
    }
}
