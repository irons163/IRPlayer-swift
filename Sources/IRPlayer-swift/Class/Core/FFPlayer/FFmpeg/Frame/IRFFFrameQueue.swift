//
//  IRFFFrameQueue.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

class IRFFFrameQueue: NSObject {
    static let maxVideoDuration: TimeInterval = 1.0
    private(set) var size: Int = 0
    var count: Int { frames.count }
    @objc dynamic private(set) var duration: TimeInterval = 0

    private var frames: [IRFFFrame] = []
    private var condition = NSCondition()
    private var destroyToken = false

    static func frameQueue() -> IRFFFrameQueue {
        return IRFFFrameQueue()
    }

    static func sleepTimeIntervalForFull() -> TimeInterval {
        return maxVideoDuration / 2.0
    }

    static func sleepTimeIntervalForFullAndPaused() -> TimeInterval {
        return maxVideoDuration / 1.1
    }

    func putFrame(_ frame: IRFFFrame?) {
        guard let frame = frame else { return }
        condition.lock()
        if destroyToken {
            condition.unlock()
            return
        }
        frames.append(frame)
        duration += frame.duration
        size += frame.size
        condition.signal()
        condition.unlock()
    }

    func putSortFrame(_ frame: IRFFFrame?) {
        guard let frame = frame else { return }
        condition.lock()
        if destroyToken {
            condition.unlock()
            return
        }
        var added = false
        if !frames.isEmpty {
            for i in stride(from: frames.count - 1, through: 0, by: -1) {
                if frame.position > frames[i].position {
                    frames.insert(frame, at: i + 1)
                    added = true
                    break
                }
            }
        }
        if !added {
            frames.append(frame)
        }
        duration += frame.duration
        size += frame.size
        condition.signal()
        condition.unlock()
    }

    func getFrameSync() -> IRFFFrame? {
        condition.lock()
        while frames.isEmpty {
            if destroyToken {
                condition.unlock()
                return nil
            }
            condition.wait()
        }
        let frame = frames.removeFirst()
        duration -= frame.duration
        if duration < 0 || count <= 0 {
            duration = 0
        }
        size -= frame.size
        if size <= 0 || count <= 0 {
            size = 0
        }
        condition.unlock()
        return frame
    }

    func getFrameAsync() -> IRFFFrame? {
        condition.lock()
        guard !destroyToken, !frames.isEmpty else {
            condition.unlock()
            return nil
        }
        let frame = frames.removeFirst()
        duration -= frame.duration
        if duration < 0 || count <= 0 {
            duration = 0
        }
        size -= frame.size
        if size <= 0 || count <= 0 {
            size = 0
        }
        condition.unlock()
        return frame
    }

    func flush() {
        condition.lock()
        frames.removeAll()
        duration = 0
        size = 0
        condition.unlock()
    }

    func destroy() {
        flush()
        condition.lock()
        destroyToken = true
        condition.broadcast()
        condition.unlock()
    }
}

