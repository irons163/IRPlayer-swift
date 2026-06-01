//
//  IRePTZShiftPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRePTZShiftPolicy {
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
