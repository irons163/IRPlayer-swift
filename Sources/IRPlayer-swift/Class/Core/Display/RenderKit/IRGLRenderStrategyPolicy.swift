//
//  IRGLRenderStrategyPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

enum IRGLRenderStrategyPolicy {
    static func strategyKind(for renderMode: IRGLRenderMode) -> IRGLRenderStrategyKind {
        if renderMode is IRGLRenderModeDistortion {
            return .distortion
        }
        if renderMode is IRGLRenderMode2DFisheye2Pano {
            return .fish2Pano
        }
        if renderMode is IRGLRenderModeVR {
            return .vr
        }
        if renderMode is IRGLRenderModeMulti4P {
            return .multi4P
        }
        if renderMode is IRGLRenderMode3DFisheye {
            return .fisheye
        }
        return .twoD
    }
}
