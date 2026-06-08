//
//  IRFFFrameTimePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import IRPlayerObjc

enum IRFFFrameTimePolicy {
    static func position(timestamp: Int64, timebase: TimeInterval) -> TimeInterval {
        guard timestamp != IR_AV_NOPTS_VALUE,
              timebase.isFinite,
              timebase > 0 else {
            return 0
        }

        let position = Double(timestamp) * timebase
        guard position.isFinite else { return 0 }
        return position
    }

    static func packetPosition(pts: Int64, dts: Int64, timebase: TimeInterval) -> TimeInterval {
        if pts != IR_AV_NOPTS_VALUE {
            return position(timestamp: pts, timebase: timebase)
        }
        return position(timestamp: dts, timebase: timebase)
    }
}
