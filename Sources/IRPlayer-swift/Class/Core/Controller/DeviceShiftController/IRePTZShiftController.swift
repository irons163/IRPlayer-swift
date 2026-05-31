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

        let adjustedDegreeX = Self.adjustedDegree(degreeX, angle: panAngle, factor: panFactor)
        let adjustedDegreeY = Self.adjustedDegree(degreeY, angle: tiltAngle, factor: tiltFactor)

        program?.didPanByDegreeX(adjustedDegreeX, degreeY: adjustedDegreeY)
    }

    static func adjustedDegree(_ degree: Float, angle: Float, factor: Float) -> Float {
        guard degree.isFinite, angle.isFinite, factor.isFinite, angle != 0 else {
            return 0
        }
        let adjustedDegree = degree * factor * 360 / angle
        guard adjustedDegree.isFinite else {
            return 0
        }
        return adjustedDegree
    }
}
