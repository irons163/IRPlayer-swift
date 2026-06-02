//
//  IRFFLogPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRFFLogPolicy {
    static func message(format: UnsafePointer<CChar>, args: CVaListPointer) -> String? {
        guard let formatString = String(validatingUTF8: format) else { return nil }
        return NSString(format: formatString, arguments: args) as String
    }

    static func write(context: UnsafeMutableRawPointer?, level: Int32, format: UnsafePointer<CChar>, args: CVaListPointer) {
        #if IRFFFFmpegLogEnable
        guard let message = message(format: format, args: args) else { return }
        print("IRFFLog: \(message)")
        #endif
    }
}
