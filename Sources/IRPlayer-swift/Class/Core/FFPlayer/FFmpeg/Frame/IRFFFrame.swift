//
//  IRFFFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation

enum IRFFFrameTime {
    static func position(timestamp: Int64, timebase: TimeInterval) -> TimeInterval {
        return IRFFFrameTimePolicy.position(timestamp: timestamp, timebase: timebase)
    }

    static func packetPosition(pts: Int64, dts: Int64, timebase: TimeInterval) -> TimeInterval {
        return IRFFFrameTimePolicy.packetPosition(pts: pts, dts: dts, timebase: timebase)
    }
}

enum IRFFFrameType: UInt, Hashable, Equatable, Sendable, RawRepresentable {
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

    func prepareForReuse() {
        playing = false
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
