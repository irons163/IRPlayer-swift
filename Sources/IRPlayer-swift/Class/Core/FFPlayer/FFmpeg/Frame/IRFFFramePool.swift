//
//  IRFFFramePool.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/30.
//

import Foundation

class IRFFFramePool: NSObject, IRFFFrameDelegate {
    var frameClassName: AnyClass
    private let frameFactory: () -> IRFFFrame?
    var lock = NSLock()
    var playingFrame: IRFFFrame?
    var unuseFrames = Set<IRFFFrame>()
    var usedFrames = Set<IRFFFrame>()

    init(capacity: Int, frameClassName: AnyClass, frameFactory: (() -> IRFFFrame?)? = nil) {
        self.frameClassName = frameClassName
        self.frameFactory = frameFactory ?? IRFFFramePool.makeFrameFactory(for: frameClassName)
        super.init()
        let reserveCapacity = Self.reserveCapacity(from: capacity)
        unuseFrames.reserveCapacity(reserveCapacity)
        usedFrames.reserveCapacity(reserveCapacity)
    }

    static func videoPool() -> IRFFFramePool {
        return IRFFFramePool(capacity: 60, frameClassName: IRFFAVYUVVideoFrame.self) {
            IRFFAVYUVVideoFrame()
        }
    }

    static func audioPool() -> IRFFFramePool {
        return IRFFFramePool(capacity: 500, frameClassName: IRFFAudioFrame.self) {
            IRFFAudioFrame()
        }
    }

    static func pool(withCapacity number: Int, frameClassName: AnyClass) -> IRFFFramePool {
        return IRFFFramePool(capacity: number, frameClassName: frameClassName)
    }

    static func reserveCapacity(from capacity: Int) -> Int {
        return IRFFFramePoolPolicy.reserveCapacity(from: capacity)
    }

    static func isFrame(_ frame: IRFFFrame?, compatibleWith frameClassName: AnyClass) -> Bool {
        return IRFFFramePoolPolicy.isFrame(frame, compatibleWith: frameClassName)
    }

    private static func makeFrameFactory(for frameClassName: AnyClass) -> () -> IRFFFrame? {
        return {
            guard let frameClass = frameClassName as? NSObject.Type else { return nil }
            return frameClass.init() as? IRFFFrame
        }
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
            guard let frame = frameFactory() else { return nil }
            frame.delegate = self
            usedFrames.insert(frame)
            return frame
        }
    }

    func setFrameUnuse(_ frame: IRFFFrame?) {
        guard Self.isFrame(frame, compatibleWith: frameClassName), let frame else { return }
        lock.lock()
        unuseFrames.insert(frame)
        usedFrames.remove(frame)
        if playingFrame == frame {
            playingFrame = nil
        }
        lock.unlock()
    }

    func setFramesUnuse(_ frames: [IRFFFrame]) {
        guard !frames.isEmpty else { return }
        lock.lock()
        for frame in frames where Self.isFrame(frame, compatibleWith: frameClassName) {
            usedFrames.remove(frame)
            unuseFrames.insert(frame)
            if playingFrame == frame {
                playingFrame = nil
            }
        }
        lock.unlock()
    }

    func setFrameStartDrawing(_ frame: IRFFFrame?) {
        guard Self.isFrame(frame, compatibleWith: frameClassName), let frame else { return }
        lock.lock()
        if let playingFrame = playingFrame {
            unuseFrames.insert(playingFrame)
        }
        playingFrame = frame
        usedFrames.remove(frame)
        lock.unlock()
    }

    func setFrameStopDrawing(_ frame: IRFFFrame?) {
        guard Self.isFrame(frame, compatibleWith: frameClassName), let frame else { return }
        lock.lock()
        if playingFrame == frame {
            unuseFrames.insert(frame)
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
        if let playingFrame {
            unuseFrames.insert(playingFrame)
            self.playingFrame = nil
        }
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

}
