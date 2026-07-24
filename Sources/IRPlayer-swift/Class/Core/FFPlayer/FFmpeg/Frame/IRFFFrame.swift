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
        return position.isFinite ? position : 0
    }

    static func packetPosition(pts: Int64, dts: Int64, timebase: TimeInterval) -> TimeInterval {
        if pts != IR_AV_NOPTS_VALUE {
            return position(
                timestamp: pts,
                timebase: timebase
            )
        }
        return position(
            timestamp: dts,
            timebase: timebase
        )
    }
}

struct IRFFFrameTransportSnapshot:
    Equatable,
    Hashable,
    Sendable
{
    let position: TimeInterval
    let duration: TimeInterval
    let size: Int
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
    private let transportLock = NSLock()
    private weak var storedDelegate: IRFFFrameDelegate?
    private var storedPlaying = false
    private var storedPosition: TimeInterval = 0
    private var storedDuration: TimeInterval = 0
    private var storedSize = 0

    var delegate: IRFFFrameDelegate? {
        get {
            transportLock.lock()
            defer { transportLock.unlock() }
            return storedDelegate
        }
        set {
            transportLock.lock()
            storedDelegate = newValue
            transportLock.unlock()
        }
    }

    var playing: Bool {
        transportLock.lock()
        defer { transportLock.unlock() }
        return storedPlaying
    }

    private(set) var type: IRFFFrameType = .video
    public var position: TimeInterval {
        get {
            transportLock.lock()
            defer { transportLock.unlock() }
            return storedPosition
        }
        set {
            transportLock.lock()
            storedPosition = newValue
            transportLock.unlock()
        }
    }

    public var duration: TimeInterval {
        get {
            transportLock.lock()
            defer { transportLock.unlock() }
            return storedDuration
        }
        set {
            transportLock.lock()
            storedDuration = newValue
            transportLock.unlock()
        }
    }

    public var size: Int {
        get {
            transportLock.lock()
            defer { transportLock.unlock() }
            return storedSize
        }
        set {
            transportLock.lock()
            storedSize = newValue
            transportLock.unlock()
        }
    }

    func startPlaying() {
        let delegate = updatePlaying(true)
        delegate?.frameDidStartPlaying(self)
    }

    func stopPlaying() {
        let delegate = updatePlaying(false)
        delegate?.frameDidStopPlaying(self)
    }

    func cancel() {
        let delegate = updatePlaying(false)
        delegate?.frameDidCancel(self)
    }

    func prepareForReuse() {
        transportLock.lock()
        storedPlaying = false
        storedPosition = 0
        storedDuration = 0
        storedSize = 0
        transportLock.unlock()
    }

    @nonobjc
    func transportSnapshot()
        -> IRFFFrameTransportSnapshot
    {
        transportLock.lock()
        defer { transportLock.unlock() }
        return IRFFFrameTransportSnapshot(
            position: storedPosition,
            duration: storedDuration,
            size: storedSize
        )
    }

    @nonobjc
    func clearDelegate(
        ifOwnedBy delegate: IRFFFrameDelegate
    ) {
        transportLock.lock()
        if storedDelegate === delegate {
            storedDelegate = nil
        }
        transportLock.unlock()
    }

    private func updatePlaying(
        _ playing: Bool
    ) -> IRFFFrameDelegate? {
        transportLock.lock()
        storedPlaying = playing
        let delegate = storedDelegate
        transportLock.unlock()
        return delegate
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

@objc protocol IRFFFrameDelegate: AnyObject {
    func frameDidStartPlaying(_ frame: IRFFFrame)
    func frameDidStopPlaying(_ frame: IRFFFrame)
    func frameDidCancel(_ frame: IRFFFrame)
}
