//
//  IRFFVideoDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/13.
//

import Foundation
import AVFoundation
import IRFFMpeg
import IRPlayerObjc

protocol IRFFVideoDecoderDelegate: AnyObject {
    func videoDecoder(_ videoDecoder: IRFFVideoDecoder, didError error: Error)
    func videoDecoderNeedUpdateBufferedDuration(_ videoDecoder: IRFFVideoDecoder)
    func videoDecoderNeedCheckBufferingStatus(_ videoDecoder: IRFFVideoDecoder)
}

class IRFFVideoDecoder {
    private struct RuntimeSnapshot {
        let canceled: Bool
        let error: NSError?
        let decoding: Bool
        let paused: Bool
        let endOfFile: Bool
        let videoToolBoxEnable: Bool
        let maxDecodeDuration: TimeInterval
    }

    private let codecContext:
        UnsafeMutablePointer<AVCodecContext>
    private let codecDescriptor: IRFFVideoCodecDescriptor?
    private let decodeFrame: IRFFDecodeFrame?
    private let packetQueue: IRFFPacketQueue
    private let frameQueue: IRFFFrameQueue
    private let framePool: IRFFFramePool
    private lazy var videoToolBox: IRFFVideoToolBox = {
        return IRFFVideoToolBox(codecContext: codecContext)
    }()
    private let sourceLock = NSLock()
    private weak var storedSource:
        IRFFVideoDecoderDataSource?
    private let runtimeLock = NSLock()
    private var runtimeCanceled = false
    private var runtimeError: NSError?
    private var runtimeDecoding = false
    private var runtimePaused = false
    private var runtimeEndOfFile = false
    private var runtimeVideoToolBoxEnable = true
    private var runtimeMaxDecodeDuration: TimeInterval = 2.0

    weak var delegate: IRFFVideoDecoderDelegate?
    var source: IRFFVideoDecoderDataSource? {
        get {
            sourceLock.lock()
            defer { sourceLock.unlock() }
            return storedSource
        }
        set {
            sourceLock.lock()
            storedSource = newValue
            sourceLock.unlock()
        }
    }
    let timebase: TimeInterval
    let fps: TimeInterval

    private var canceled: Bool {
        get { runtimeSnapshot().canceled }
        set {
            runtimeLock.lock()
            runtimeCanceled = newValue
            runtimeLock.unlock()
        }
    }

    private(set) var error: NSError? {
        get { runtimeSnapshot().error }
        set {
            runtimeLock.lock()
            runtimeError = newValue
            runtimeLock.unlock()
        }
    }

    private(set) var decoding: Bool {
        get { runtimeSnapshot().decoding }
        set {
            runtimeLock.lock()
            runtimeDecoding = newValue
            runtimeLock.unlock()
        }
    }

    var paused: Bool {
        get { runtimeSnapshot().paused }
        set {
            runtimeLock.lock()
            runtimePaused = newValue
            runtimeLock.unlock()
        }
    }

    var endOfFile: Bool {
        get { runtimeSnapshot().endOfFile }
        set {
            runtimeLock.lock()
            runtimeEndOfFile = newValue
            runtimeLock.unlock()
        }
    }

    var videoToolBoxEnable: Bool {
        get { runtimeSnapshot().videoToolBoxEnable }
        set {
            runtimeLock.lock()
            runtimeVideoToolBoxEnable = newValue
            runtimeLock.unlock()
        }
    }

    var maxDecodeDuration: TimeInterval {
        get { runtimeSnapshot().maxDecodeDuration }
        set {
            runtimeLock.lock()
            runtimeMaxDecodeDuration = newValue
            runtimeLock.unlock()
        }
    }

    init(codecContext: UnsafeMutablePointer<AVCodecContext>, timebase: TimeInterval, fps: TimeInterval, delegate: IRFFVideoDecoderDelegate?) {
        self.codecContext = codecContext
        self.codecDescriptor = IRFFVideoCodecDescriptor(
            copying: codecContext
        )
        self.timebase = timebase
        self.fps = fps
        self.delegate = delegate
        self.decodeFrame = IRFFDecodeFrame()
        self.packetQueue = IRFFPacketQueue(timebase: timebase)
        self.frameQueue = IRFFFrameQueue()
        self.framePool = IRFFFramePool.videoPool()
    }

    func packetSize() -> Int {
        return Int(packetQueue.size)
    }

    func empty() -> Bool {
        return packetEmpty() && frameEmpty()
    }

    func packetEmpty() -> Bool {
        return packetQueue.count <= 0
    }

    func frameEmpty() -> Bool {
        return frameQueue.count <= 0
    }

    func duration() -> TimeInterval {
        return packetDuration() + frameDuration()
    }

    func packetDuration() -> TimeInterval {
        return packetQueue.duration
    }

    func frameDuration() -> TimeInterval {
        return frameQueue.duration
    }

    static func frameDuration(ticks: Int64, repeatPicture: Int32, timebase: TimeInterval, fps: TimeInterval) -> TimeInterval {
        if ticks != 0 {
            guard timebase.isFinite, timebase > 0 else {
                return 0
            }
            let baseDuration =
                TimeInterval(ticks) * timebase
            let repeatDuration =
                TimeInterval(max(0, repeatPicture)) *
                timebase *
                0.5
            let duration = baseDuration + repeatDuration
            return baseDuration.isFinite &&
                repeatDuration.isFinite &&
                duration.isFinite &&
                duration > 0
                ? duration
                : 0
        }

        guard fps.isFinite, fps > 0 else { return 0 }
        let duration = 1 / fps
        return duration.isFinite && duration > 0
            ? duration
            : 0
    }

    static func decodeBackpressureSleepInterval(frameDuration: TimeInterval,
                                                maxDecodeDuration: TimeInterval,
                                                paused: Bool) -> TimeInterval? {
        guard frameDuration.isFinite,
              maxDecodeDuration.isFinite,
              maxDecodeDuration > 0,
              frameDuration >= maxDecodeDuration else {
            return nil
        }
        return paused ? 0.5 : 0.1
    }

    static func packetDecodeResultIsFailure(_ result: Int32) -> Bool {
        return IRFFDecodeResult.isFailure(result)
    }

    static func shouldFinishDecode(endOfFile: Bool, packetEmpty: Bool) -> Bool {
        return endOfFile && packetEmpty
    }

    static func decodeIdleSleepInterval(paused: Bool) -> TimeInterval? {
        return paused ? 0.01 : nil
    }

    static func shouldCreateYUVFrame(hasFrame: Bool,
                                     hasLuma: Bool,
                                     hasChromaB: Bool,
                                     hasChromaR: Bool) -> Bool {
        return hasFrame &&
            hasLuma &&
            hasChromaB &&
            hasChromaR
    }

    static func packetQueueFallbackDuration(packetDuration: Int64,
                                            packetSize: Int32,
                                            timebase: TimeInterval,
                                            fps: TimeInterval) -> TimeInterval {
        guard packetDuration <= 0, packetSize > 0 else {
            return 0
        }
        return frameDuration(
            ticks: 0,
            repeatPicture: 0,
            timebase: timebase,
            fps: fps
        )
    }

    func waitForFrame() -> IRFFVideoFrame? {
        return frameQueue.waitForFrame() as? IRFFVideoFrame
    }

    func dequeueFrame() -> IRFFVideoFrame? {
        return frameQueue.dequeue() as? IRFFVideoFrame
    }

    func putPacket(_ packet: IRFFPacket) {
        guard let snapshot = packet.snapshot else {
            packet.close()
            return
        }
        let duration = Self.packetQueueFallbackDuration(
            packetDuration: snapshot.duration,
            packetSize: snapshot.size,
            timebase: timebase,
            fps: fps
        )
        packetQueue.putPacket(packet, duration: duration)
    }

    func flush() {
        packetQueue.flush()
        frameQueue.flush()
        framePool.flush()
        packetQueue.putFlush()
    }

    func destroy() {
        canceled = true
        frameQueue.close()
        packetQueue.destroy()
        framePool.close()
    }

    func decodeFrameThread() {
        decoding = true
        decodeLoop: while true {
            let runtime = runtimeSnapshot()
            if runtime.canceled || runtime.error != nil {
                IRFFRuntimeDebugOutput.write("decode video thread quit")
                break
            }
            if let sleepTime = Self.decodeIdleSleepInterval(paused: runtime.paused) {
                Thread.sleep(forTimeInterval: sleepTime)
                continue
            }
            if Self.shouldFinishDecode(endOfFile: runtime.endOfFile, packetEmpty: packetEmpty()) {
                IRFFRuntimeDebugOutput.write("decode video finished")
                break
            }
            if let interval = Self.decodeBackpressureSleepInterval(frameDuration: frameDuration(),
                                                                   maxDecodeDuration: runtime.maxDecodeDuration,
                                                                   paused: runtime.paused) {
                IRFFRuntimeDebugOutput.write("decode video thread sleep : \(interval)")
                Thread.sleep(forTimeInterval: interval)
                continue
            }

            let item = packetQueue.getItem()
            let packetRuntime = runtimeSnapshot()
            if packetRuntime.canceled || packetRuntime.error != nil {
                if case let .packet(packet) = item {
                    packet.close()
                }
                break
            }

            switch item {
            case .closed:
                break decodeLoop
            case .flush:
                IRFFRuntimeDebugOutput.write("video codec flush")
                avcodec_flush_buffers(codecContext)
                videoToolBox.flush()
                continue
            case let .packet(packet):
                if packetRuntime.endOfFile {
                    delegate?
                        .videoDecoderNeedUpdateBufferedDuration(
                            self
                        )
                }
                guard let snapshot = packet.snapshot,
                      snapshot.streamIndex >= 0,
                      snapshot.hasData else {
                    packet.close()
                    continue
                }

                var decodedFrame: IRFFVideoFrame?
                let didBorrow = packet.withPacket {
                    borrowedPacket in
                    decodedFrame = decodeFrame(
                        packet: borrowedPacket
                    )
                    return true
                }
                packet.close()
                if didBorrow, let decodedFrame {
                    frameQueue.enqueueSorted(decodedFrame)
                }
            }
        }
        decoding = false
        delegate?.videoDecoderNeedCheckBufferingStatus(self)
    }

    private func decodeFrame(packet: AVPacket) -> IRFFVideoFrame? {
        let runtime = runtimeSnapshot()
        if let source,
           let codecDescriptor,
           let packetValue = IRFFCompressedVideoPacket(
                copying: packet
           ) {
            let info = IRFFVideoDecoderInfo(
                codec: codecDescriptor,
                isHardwareDecodingEnabled:
                    runtime.videoToolBoxEnable,
                maximumDecodeDuration:
                    runtime.maxDecodeDuration,
                timebase: timebase,
                framesPerSecond: fps
            )
            if source.shouldHandle(
                info,
                decodeFrame: packetValue
            ) {
                return source.videoDecoder(
                    info,
                    decodeFrame: packetValue
                )
            }
        }

        if runtime.videoToolBoxEnable && codecContext.pointee.codec_id == AV_CODEC_ID_H264 {
            if videoToolBox.trySetupVTSession() {
                if videoToolBox.sendPacket(packet) {
                     return videoFrameFromVideoToolBox(packet: packet)
                }
            }
        }

        return decodeFrameWithFFmpeg(packet: packet)
    }

    private func decodeFrameWithFFmpeg(packet: AVPacket) -> IRFFVideoFrame? {
        var packet = packet
        var result = avcodec_send_packet(codecContext, &packet)
        if Self.packetDecodeResultIsFailure(result) {
            handleDecodingError(IRFFCheckError(result))
            delegateErrorCallback()
            return nil
        }
        while result >= 0 {
            guard let decodeFrame else { return nil }
            var receivedFrame:
                IRFFAVYUVVideoFrame?
            var receiveResult: Int32 = -1
            let didBorrow = decodeFrame.withFrame {
                frame in
                receiveResult = avcodec_receive_frame(
                    codecContext,
                    frame
                )
                if receiveResult >= 0 {
                    receivedFrame =
                        videoFrame(
                            fromDecodedFrame: frame
                        )
                }
                return true
            }
            guard didBorrow else { return nil }
            result = receiveResult
            if result < 0 {
                if Self.packetDecodeResultIsFailure(result) {
                    handleDecodingError(IRFFCheckError(result))
                    return nil
                }
                break
            }
            return receivedFrame
        }
        return nil
    }

    private func videoFrame(
        fromDecodedFrame frame:
            UnsafeMutablePointer<AVFrame>
    ) -> IRFFAVYUVVideoFrame? {
        guard Self.shouldCreateYUVFrame(
            hasFrame: true,
            hasLuma: frame.pointee.data.0 != nil,
            hasChromaB: frame.pointee.data.1 != nil,
            hasChromaR: frame.pointee.data.2 != nil
        ) else {
            return nil
        }

        guard let videoFrame =
                framePool.leaseFrame()
                    as? IRFFAVYUVVideoFrame else {
            return nil
        }
        videoFrame.setFrameData(frame, width: Int(codecContext.pointee.width), height: Int(codecContext.pointee.height))
        videoFrame.position = IRFFFrameTime.position(timestamp: frame.pointee.best_effort_timestamp, timebase: timebase)

        videoFrame.duration = Self.frameDuration(ticks: frame.pointee.duration,
                                                 repeatPicture: frame.pointee.repeat_pict,
                                                 timebase: timebase,
                                                 fps: fps)
        return videoFrame
    }

    private func videoFrameFromVideoToolBox(packet: AVPacket) -> IRFFVideoFrame? {
        guard let imageBuffer = videoToolBox.imageBuffer() else {
            return nil
        }

        let videoFrame = IRFFCVYUVVideoFrame(pixelBuffer: imageBuffer)
        videoFrame.position = IRFFFrameTime.packetPosition(pts: packet.pts, dts: packet.dts, timebase: timebase)

        videoFrame.duration = Self.frameDuration(ticks: packet.duration,
                                                 repeatPicture: 0,
                                                 timebase: timebase,
                                                 fps: fps)
        return videoFrame
    }

    private func handleDecodingError(_ error: NSError?) {
        self.error = error
        delegateErrorCallback()
    }

    private func delegateErrorCallback() {
        if let error = error {
            delegate?.videoDecoder(self, didError: error)
        }
    }

    private func runtimeSnapshot() -> RuntimeSnapshot {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        return RuntimeSnapshot(
            canceled: runtimeCanceled,
            error: runtimeError,
            decoding: runtimeDecoding,
            paused: runtimePaused,
            endOfFile: runtimeEndOfFile,
            videoToolBoxEnable: runtimeVideoToolBoxEnable,
            maxDecodeDuration: runtimeMaxDecodeDuration
        )
    }

}

extension IRFFVideoDecoder: IRFFDecoderVideoOutput {
    func send(videoFrame: IRFFVideoFrame) {
        self.frameQueue.enqueueSorted(videoFrame)
    }
}
