//
//  IRFFFrameQueuePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRFFFrameQueuePolicy {
    static func sleepTimeIntervalForFull(maxVideoDuration: TimeInterval) -> TimeInterval {
        return maxVideoDuration / 2.0
    }

    static func sleepTimeIntervalForFullAndPaused(maxVideoDuration: TimeInterval) -> TimeInterval {
        return maxVideoDuration / 1.1
    }

    static func accountedDuration(for frame: IRFFFrame) -> TimeInterval {
        guard frame.duration.isFinite, frame.duration > 0 else { return 0 }
        return frame.duration
    }

    static func accountedSize(for frame: IRFFFrame) -> Int {
        return max(0, frame.size)
    }

    static func shouldInsert(_ frame: IRFFFrame, after existingFrame: IRFFFrame) -> Bool {
        if frame.position.isFinite, existingFrame.position.isFinite {
            return frame.position >= existingFrame.position
        }
        if !frame.position.isFinite {
            return true
        }
        return false
    }
}
