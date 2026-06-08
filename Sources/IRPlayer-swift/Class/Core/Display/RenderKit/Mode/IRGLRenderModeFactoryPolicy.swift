//
//  IRGLRenderModeFactoryPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

enum IRGLRenderModeFactoryPolicy {
    enum ModePlan: Equatable {
        case normal2D
        case normal2DNamed(name: String, shiftEnabled: Bool)
        case panorama(name: String, wideDegreeX: Float, wideDegreeY: Float)
        case fisheye3D(name: String)
        case multi4P(name: String)
    }

    static func normalModePlan() -> [ModePlan] {
        [.normal2D]
    }

    static func panoramaModePlan() -> ModePlan {
        .panorama(name: "", wideDegreeX: 360, wideDegreeY: 20)
    }

    static func fisheyeModePlan() -> [ModePlan] {
        [
            .panorama(name: "Panorama", wideDegreeX: 360, wideDegreeY: 20),
            .fisheye3D(name: "Onelen"),
            .multi4P(name: "Fourlens"),
            .normal2DNamed(name: "Rawdata", shiftEnabled: false)
        ]
    }
}
