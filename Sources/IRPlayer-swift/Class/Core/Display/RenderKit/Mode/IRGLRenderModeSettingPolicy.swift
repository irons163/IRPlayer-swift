//
//  IRGLRenderModeSettingPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

enum IRGLRenderModeSettingPolicy {
    enum Action: Equatable {
        case defaultScale
        case wideDegreeX
        case wideDegreeY
        case contentMode
        case scaleRange
        case scopeRange
        case none
    }

    static func action(for key: String) -> Action {
        switch IRGLRenderModeConfigurationKey(rawValue: key) {
        case .setDefaultScale:
            return .defaultScale
        case .setWideDegreeX:
            return .wideDegreeX
        case .setWideDegreeY:
            return .wideDegreeY
        case .setContentMode:
            return .contentMode
        case .setScaleRange:
            return .scaleRange
        case .setScopeRange:
            return .scopeRange
        case nil:
            return .none
        }
    }
}
