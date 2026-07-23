//
//  IRFFFrameQueue.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

class IRFFFrameQueue: NSObject {
    static let maxVideoDuration: TimeInterval = 1.0

    private var frames: [IRFFFrame] = []
    private let condition = NSCondition()
    private var storedSize: Int = 0
    private var storedDuration: TimeInterval = 0
    private var destroyToken = false

    var size: Int {
        condition.lock()
        defer { condition.unlock() }
        return storedSize
    }

    var count: Int {
        condition.lock()
        defer { condition.unlock() }
        return frames.count
    }

    @objc dynamic var duration: TimeInterval {
        condition.lock()
        defer { condition.unlock() }
        return storedDuration
    }

    static func frameQueue() -> IRFFFrameQueue {
        return IRFFFrameQueue()
    }

    static func sleepTimeIntervalForFull() -> TimeInterval {
        return IRFFFrameQueuePolicy.sleepTimeIntervalForFull(maxVideoDuration: maxVideoDuration)
    }

    static func sleepTimeIntervalForFullAndPaused() -> TimeInterval {
        return IRFFFrameQueuePolicy.sleepTimeIntervalForFullAndPaused(maxVideoDuration: maxVideoDuration)
    }

    static func accountedDuration(for frame: IRFFFrame) -> TimeInterval {
        return IRFFFrameQueuePolicy.accountedDuration(for: frame)
    }

    static func accountedSize(for frame: IRFFFrame) -> Int {
        return IRFFFrameQueuePolicy.accountedSize(for: frame)
    }

    static func shouldInsert(_ frame: IRFFFrame, after existingFrame: IRFFFrame) -> Bool {
        return IRFFFrameQueuePolicy.shouldInsert(frame, after: existingFrame)
    }

    func putFrame(_ frame: IRFFFrame?) {
        guard let frame = frame else { return }
        condition.lock()
        if destroyToken {
            condition.unlock()
            return
        }
        frames.append(frame)
        storedDuration += Self.accountedDuration(for: frame)
        storedSize += Self.accountedSize(for: frame)
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
                if Self.shouldInsert(frame, after: frames[i]) {
                    frames.insert(frame, at: i + 1)
                    added = true
                    break
                }
            }
        }
        if !added {
            frames.insert(frame, at: 0)
        }
        storedDuration += Self.accountedDuration(for: frame)
        storedSize += Self.accountedSize(for: frame)
        condition.signal()
        condition.unlock()
    }

    func getFrameSync() -> IRFFFrame? {
        // Poll instead of blocking on condition.wait() to avoid a priority inversion
        // warning from the Thread Performance Checker. NSCondition.wait() is an
        // indefinite block — the checker fires whenever a high-QoS thread waits on a
        // condition that a lower-QoS thread must signal, regardless of the queue's QoS
        // setting. A 5 ms sleep is imperceptible at 30/60 fps.
        while true {
            condition.lock()
            if destroyToken {
                condition.unlock()
                return nil
            }
            if !frames.isEmpty {
                let frame = frames.removeFirst()
                storedDuration -= Self.accountedDuration(for: frame)
                if storedDuration < 0 || frames.isEmpty {
                    storedDuration = 0
                }
                storedSize -= Self.accountedSize(for: frame)
                if storedSize <= 0 || frames.isEmpty {
                    storedSize = 0
                }
                condition.unlock()
                return frame
            }
            condition.unlock()
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    func getFrameAsync() -> IRFFFrame? {
        condition.lock()
        guard !destroyToken, !frames.isEmpty else {
            condition.unlock()
            return nil
        }
        let frame = frames.removeFirst()
        storedDuration -= Self.accountedDuration(for: frame)
        if storedDuration < 0 || frames.isEmpty {
            storedDuration = 0
        }
        storedSize -= Self.accountedSize(for: frame)
        if storedSize <= 0 || frames.isEmpty {
            storedSize = 0
        }
        condition.unlock()
        return frame
    }

    func flush() {
        condition.lock()
        flushLocked()
        condition.unlock()
    }

    func destroy() {
        condition.lock()
        flushLocked()
        destroyToken = true
        condition.broadcast()
        condition.unlock()
    }

    private func flushLocked() {
        frames.removeAll()
        storedDuration = 0
        storedSize = 0
    }
}
