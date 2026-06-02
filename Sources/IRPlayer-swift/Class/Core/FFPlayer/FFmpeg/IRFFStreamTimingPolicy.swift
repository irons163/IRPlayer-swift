//
//  IRFFStreamTimingPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import IRFFMpeg

enum IRFFStreamTimingPolicy {
    static func finitePositiveValueOrDefault(_ value: Double, defaultValue: Double) -> Double {
        return value.isFinite && value > 0 ? value : defaultValue
    }

    static func timebase(_ stream: UnsafePointer<AVStream>, defaultTimebase: Double) -> Double {
        let timebase: Double
        if stream.pointee.time_base.den > 0 && stream.pointee.time_base.num > 0 {
            timebase = av_q2d(stream.pointee.time_base)
        } else {
            timebase = defaultTimebase
        }
        return finitePositiveValueOrDefault(timebase, defaultValue: 1.0)
    }

    static func fps(_ stream: UnsafePointer<AVStream>, timebase: Double) -> Double {
        let fps: Double
        if stream.pointee.avg_frame_rate.den > 0 && stream.pointee.avg_frame_rate.num > 0 {
            fps = av_q2d(stream.pointee.avg_frame_rate)
        } else if stream.pointee.r_frame_rate.den > 0 && stream.pointee.r_frame_rate.num > 0 {
            fps = av_q2d(stream.pointee.r_frame_rate)
        } else if timebase > 0 {
            fps = 1.0 / timebase
        } else {
            fps = 1.0
        }
        return finitePositiveValueOrDefault(fps, defaultValue: 1.0)
    }
}
