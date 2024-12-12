//
//  IRFFFramePool.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

class IRFFFramePool: NSObject, IRFFFrameDelegate {
    var frameClassName: AnyClass
    var lock = NSLock()
    var playingFrame: IRFFFrame?
    var unuseFrames = Set<IRFFFrame>()
    var usedFrames = Set<IRFFFrame>()

    init(capacity: Int, frameClassName: AnyClass) {
        self.frameClassName = frameClassName
        super.init()
        unuseFrames.reserveCapacity(capacity)
        usedFrames.reserveCapacity(capacity)
    }

    static func videoPool() -> IRFFFramePool {
        return IRFFFramePool(capacity: 60, frameClassName: NSClassFromString("IRPlayerSwift.IRFFAVYUVVideoFrame")!)
    }

    static func audioPool() -> IRFFFramePool {
        return IRFFFramePool(capacity: 500, frameClassName: NSClassFromString("IRPlayerSwift.IRFFAudioFrame")!)
    }

    static func pool(withCapacity number: Int, frameClassName: AnyClass) -> IRFFFramePool {
        return IRFFFramePool(capacity: number, frameClassName: frameClassName)
    }

    var count: Int {
        return unuseCount + usedCount + (playingFrame != nil ? 1 : 0)
    }

    var unuseCount: Int {
        return unuseFrames.count
    }

    var usedCount: Int {
        return usedFrames.count
    }

    func getUnuseFrame() -> IRFFFrame? {
        lock.lock()
        defer { lock.unlock() }

        if let frame = unuseFrames.popFirst() {
            usedFrames.insert(frame)
            return frame
        } else {
            let frame = frameClassName.alloc() as! IRFFFrame
            frame.delegate = self
            usedFrames.insert(frame)
            return frame
        }
    }

    func setFrameUnuse(_ frame: IRFFFrame?) {
        guard let frame = frame, frame.isKind(of: frameClassName) else { return }
        lock.lock()
        unuseFrames.insert(frame)
        usedFrames.remove(frame)
        lock.unlock()
    }

    func setFramesUnuse(_ frames: [IRFFFrame]) {
        guard !frames.isEmpty else { return }
        lock.lock()
        for frame in frames where frame.isKind(of: frameClassName) {
            usedFrames.remove(frame)
            unuseFrames.insert(frame)
        }
        lock.unlock()
    }

    func setFrameStartDrawing(_ frame: IRFFFrame?) {
        guard let frame = frame, frame.isKind(of: frameClassName) else { return }
        lock.lock()
        if let playingFrame = playingFrame {
            unuseFrames.insert(playingFrame)
        }
        playingFrame = frame
        usedFrames.remove(playingFrame!)
        lock.unlock()
    }

    func setFrameStopDrawing(_ frame: IRFFFrame?) {
        guard let frame = frame, frame.isKind(of: frameClassName) else { return }
        lock.lock()
        if playingFrame == frame {
            unuseFrames.insert(playingFrame!)
            playingFrame = nil
        }
        lock.unlock()
    }

    func flush() {
        lock.lock()
        for frame in usedFrames {
            unuseFrames.insert(frame)
        }
        usedFrames.removeAll()
        lock.unlock()
    }

    // MARK: - IRFFFrameDelegate

    func frameDidStartPlaying(_ frame: IRFFFrame) {
        setFrameStartDrawing(frame)
    }

    func frameDidStopPlaying(_ frame: IRFFFrame) {
        setFrameStopDrawing(frame)
    }

    func frameDidCancel(_ frame: IRFFFrame) {
        setFrameUnuse(frame)
    }

    deinit {
        print("IRFFFramePool release")
    }
}
