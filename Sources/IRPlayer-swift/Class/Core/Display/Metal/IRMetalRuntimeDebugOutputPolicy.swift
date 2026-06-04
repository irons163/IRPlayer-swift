//
//  IRMetalRuntimeDebugOutputPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRMetalRuntimeDebugOutputPolicy {
    #if IRMetalRuntimeDebugOutputEnable
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print(message())
    }
}
