//
//  IRPlayerTestSupport.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
@testable import IRPlayer_swift

final class FormatContextInterruptDelegate: IRFFFormatContextDelegate {
    var shouldInterrupt: Bool

    init(shouldInterrupt: Bool) {
        self.shouldInterrupt = shouldInterrupt
    }

    func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool {
        shouldInterrupt
    }
}

final class ShaderParamsDelegateSpy: IRGLShaderParamsDelegate {
    private(set) var outputSizes: [(width: Int, height: Int)] = []

    func didUpdateOutputWH(_ w: Int, _ h: Int) {
        outputSizes.append((w, h))
    }
}

func mirroredFFPlayer(from player: IRPlayerImp) -> IRFFPlayer? {
    let childValue = Mirror(reflecting: player)
        .children
        .first { $0.label == "_ffPlayer" }?
        .value
    guard let childValue = childValue else { return nil }

    let optionalMirror = Mirror(reflecting: childValue)
    if optionalMirror.displayStyle == .optional {
        return optionalMirror.children.first?.value as? IRFFPlayer
    }
    return childValue as? IRFFPlayer
}
