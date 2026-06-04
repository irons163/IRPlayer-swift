//
//  IRPlayerTestSupport.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import Darwin
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

func captureStandardOutput(_ body: () -> Void) -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    fflush(stdout)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    body()

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
