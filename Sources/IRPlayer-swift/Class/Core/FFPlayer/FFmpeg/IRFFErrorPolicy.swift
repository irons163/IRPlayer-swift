//
//  IRFFErrorPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import IRFFMpeg

enum IRFFErrorPolicy {
    static func error(result: Int32, errorCode: Int) -> NSError? {
        guard result < 0 else { return nil }

        var errorBuffer = [CChar](repeating: 0, count: 256)
        av_strerror(result, &errorBuffer, errorBuffer.count)

        let errorString = String(cString: errorBuffer)
        let errorDescription = "ffmpeg code: \(result), ffmpeg msg: \(errorString)"
        return NSError(domain: errorDescription, code: errorCode, userInfo: nil)
    }
}
