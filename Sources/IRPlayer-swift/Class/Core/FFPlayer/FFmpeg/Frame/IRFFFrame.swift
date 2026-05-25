//
//  IRFFFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation
import IRPlayerObjc

enum IRFFFrameTime {
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

enum IRFFFrameType: UInt {
    case video
    case avyuvVideo
    case cvyuvVideo
    case audio
    case subtitle
    case artwork
}

@objcMembers public class IRFFFrame: NSObject {
    public weak var delegate: IRFFFrameDelegate?
    private(set) var playing: Bool = false

    private(set) var type: IRFFFrameType = .video
    public var position: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var size: Int = 0

    func startPlaying() {
        playing = true
        delegate?.frameDidStartPlaying(self)
    }

    func stopPlaying() {
        playing = false
        delegate?.frameDidStopPlaying(self)
    }

    func cancel() {
        playing = false
        delegate?.frameDidCancel(self)
    }
}

@objcMembers public class IRFFSubtitleFrame: IRFFFrame {
    override var type: IRFFFrameType {
        return .subtitle
    }
}

@objcMembers public class IRFFArtworkFrame: IRFFFrame {
    public var picture: Data?

    override var type: IRFFFrameType {
        return .artwork
    }
}

@objc public protocol IRFFFrameDelegate: AnyObject {
    func frameDidStartPlaying(_ frame: IRFFFrame)
    func frameDidStopPlaying(_ frame: IRFFFrame)
    func frameDidCancel(_ frame: IRFFFrame)
}
