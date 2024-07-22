//
//  IRFFDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/11.
//

import Foundation
import CoreGraphics
import AVFoundation

protocol IRFFDecoderDelegate: AnyObject {
    func decoderWillOpenInputStream(_ decoder: IRFFDecoder)
    func decoderDidPrepareToDecodeFrames(_ decoder: IRFFDecoder)
    func decoderDidEndOfFile(_ decoder: IRFFDecoder)
    func decoderDidPlaybackFinished(_ decoder: IRFFDecoder)
    func decoder(_ decoder: IRFFDecoder, didError error: Error)
    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBuffering buffering: Bool)
    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBufferedDuration bufferedDuration: TimeInterval)
    func decoder(_ decoder: IRFFDecoder, didChangeValueOfProgress progress: TimeInterval)
}

@objc public protocol IRFFDecoderVideoOutput: NSObjectProtocol {
    @objc optional func decoder(_ decoder: IRFFDecoder?, renderVideoFrame videoFrame: IRFFVideoFrame)
}

@objc protocol IRFFDecoderAudioOutput: AnyObject {
    var numberOfChannels: UInt32 { get }
    var samplingRate: Float64 { get }
}

@objcMembers public class IRFFDecoder: NSObject {

    weak var delegate: IRFFDecoderDelegate?
    weak var videoOutput: IRFFDecoderVideoOutput?
    weak var audioOutput: IRFFDecoderAudioOutput?

    private var ffmpegOperationQueue: OperationQueue? = OperationQueue()
    private var openFileOperation: Operation?
    private var readPacketOperation: Operation?
    private var decodeFrameOperation: Operation?
    private var displayOperation: Operation?

    private var formatContext: IRFFFormatContext?
    private var audioDecoder: IRFFAudioDecoder?
    private var videoDecoder: IRFFVideoDecoder?

    private(set) var error: Error?
    private(set) var contentURL: URL
    private(set) var progress: TimeInterval = 0
    private(set) var bufferedDuration: TimeInterval = 0 {
        didSet {
            guard bufferedDuration != oldValue else {
                return
            }
            if (bufferedDuration <= 0.000001) {
                bufferedDuration = 0
            }
            delegate?.decoder(self, didChangeValueOfBufferedDuration: bufferedDuration)
            if bufferedDuration <= 0 && endOfFile {
                playbackFinished = true
            }
            checkBufferingStatus()
        }
    }
    private(set) var buffering: Bool = false
    private(set) var playbackFinished: Bool = false
    private(set) var closed: Bool = false
    private(set) var endOfFile: Bool = false
    private(set) var paused: Bool = false
    private(set) var seeking: Bool = false
    private(set) var prepareToDecode: Bool = false

    private var seekToTime: TimeInterval = 0
    private var seekMinTime: TimeInterval = 0
    private var seekCompleteHandler: ((Bool) -> Void)?
    private var selectAudioTrack = false
    private var selectAudioTrackIndex = 0
    private var currentVideoFrame: IRFFVideoFrame?
    private var currentAudioFrame: IRFFAudioFrame?

    private(set) var audioTimeClock: TimeInterval = 0

    var hardwareDecoderEnable: Bool = true
    var minBufferedDuration: TimeInterval = 0
    var reading = false

    var videoEnable: Bool {
        return formatContext?.videoEnable ?? false
    }

    var audioEnable: Bool {
        return formatContext?.audioEnable ?? false
    }

    var videoTrack: IRFFTrack? {
        return formatContext?.videoTrack
    }

    var audioTrack: IRFFTrack? {
        return formatContext?.audioTrack
    }

    var videoTracks: [IRFFTrack] {
        return formatContext?.videoTracks ?? []
    }

    var audioTracks: [IRFFTrack] {
        return formatContext?.audioTracks ?? []
    }

    var metadata: [String: Any] {
        return formatContext?.metadata as? [String: Any] ?? [:]
    }

    var presentationSize: CGSize {
        return formatContext?.videoPresentationSize ?? .zero
    }

    var aspect: CGFloat {
        return formatContext?.videoAspect ?? 0
    }

    var duration: TimeInterval {
        return formatContext?.duration ?? 0
    }

    var bitrate: TimeInterval {
        return formatContext?.bitrate ?? 0
    }

    var seekEnable: Bool {
        return duration > 0
    }

    init(contentURL: URL, delegate: IRFFDecoderDelegate?, videoOutput: IRFFDecoderVideoOutput?, audioOutput: IRFFDecoderAudioOutput?) {
        self.contentURL = contentURL
        self.delegate = delegate
        self.videoOutput = videoOutput
        self.audioOutput = audioOutput
        super.init()
        setupFFmpeg()
    }

    private func setupFFmpeg() {
        DispatchQueue.once(token: "ffmpeg.setup") {
            av_log_set_callback { context, level, format, args in
                guard let format = format,
                      let formatString = String.init(utf8String: format),
                      let args = args else {
                    return
                }
                let message = NSString(format: formatString, arguments: args) as String
                switch level {
                default:
                    print(message.trimmingCharacters(in: .newlines))
                    break;
                }
            }
            av_register_all()
            avformat_network_init()
        }
    }

    func open() {
        setupOperationQueue()
    }

    private func setupOperationQueue() {
        ffmpegOperationQueue?.maxConcurrentOperationCount = 3
        ffmpegOperationQueue?.qualityOfService = .userInteractive
        setupOpenFileOperation()
    }

    private func setupOpenFileOperation() {
        openFileOperation = BlockOperation { [weak self] in
            self?.openFormatContext()
        }
        openFileOperation?.queuePriority = .veryHigh
        openFileOperation?.qualityOfService = .userInteractive
        ffmpegOperationQueue?.addOperation(openFileOperation!)
    }

    private func setupReadPacketOperation() {
        if error != nil {
            delegateErrorCallback()
            return
        }
        if readPacketOperation == nil || readPacketOperation!.isFinished {
            readPacketOperation = BlockOperation { [weak self] in
                self?.readPacketThread()
            }
            readPacketOperation?.queuePriority = .veryHigh
            readPacketOperation?.qualityOfService = .userInteractive
            readPacketOperation?.addDependency(openFileOperation!)
            ffmpegOperationQueue?.addOperation(readPacketOperation!)
        }
        if formatContext?.videoEnable == true {
            if decodeFrameOperation == nil || decodeFrameOperation!.isFinished {
                decodeFrameOperation = BlockOperation { [weak self] in
                    self?.videoDecoder?.decodeFrameThread()
                }
                decodeFrameOperation?.queuePriority = .veryHigh
                decodeFrameOperation?.qualityOfService = .userInteractive
                decodeFrameOperation?.addDependency(openFileOperation!)
                ffmpegOperationQueue?.addOperation(decodeFrameOperation!)
            }
            if displayOperation == nil || displayOperation!.isFinished {
                displayOperation = BlockOperation { [weak self] in
                    self?.displayThread()
                }
                displayOperation?.queuePriority = .veryHigh
                displayOperation?.qualityOfService = .userInteractive
                displayOperation?.addDependency(openFileOperation!)
                ffmpegOperationQueue?.addOperation(displayOperation!)
            }
        }
    }

    private func openFormatContext() {
        delegate?.decoderWillOpenInputStream(self)
        formatContext = IRFFFormatContext(contentURL: contentURL, delegate: self)
        formatContext?.setupSync()
        if let formatError = formatContext?.error {
            error = formatError
            delegateErrorCallback()
            return
        }
        prepareToDecode = true
        delegate?.decoderDidPrepareToDecodeFrames(self)
        if formatContext?.videoEnable == true {
            videoDecoder = IRFFVideoDecoder(codecContext: formatContext!.video_codec_context, timebase: formatContext!.videoTimebase, fps: formatContext!.videoFPS, delegate: self)
            videoDecoder?.videoToolBoxEnable = hardwareDecoderEnable
        }
        if formatContext?.audioEnable == true {
            audioDecoder = IRFFAudioDecoder.decoder(codecContext: formatContext!.audio_codec_context, timebase: formatContext!.audioTimebase, delegate: self)
        }
        setupReadPacketOperation()
    }

    private func readPacketThread() {
        videoDecoder?.flush()
        audioDecoder?.flush()
        reading = true
        var finished = false
        var packet = AVPacket()
        while !finished {
            if closed || error != nil {
                print("read packet thread quit")
                break
            }
            if seeking {
                endOfFile = false
                playbackFinished = false
                formatContext?.seekFile(withFFTimebase: seekToTime)
                buffering = true
                audioDecoder?.flush()
                videoDecoder?.flush()
                videoDecoder?.paused = false
                videoDecoder?.endOfFile = false
                seeking = false
                seekToTime = 0
                if let handler = seekCompleteHandler {
                    handler(true)
                    seekCompleteHandler = nil
                }
                audioTimeClock = progress
                currentVideoFrame = nil
                currentAudioFrame = nil
                updateBufferedDurationByVideo()
                updateBufferedDurationByAudio()
                continue
            }
            if selectAudioTrack {
                if formatContext?.selectAudioTrackIndex(Int32(selectAudioTrackIndex)) == nil {
                    audioDecoder?.destroy()
                    audioDecoder = IRFFAudioDecoder.decoder(codecContext: formatContext!.audio_codec_context, timebase: formatContext!.audioTimebase, delegate: self)
                    if !playbackFinished {
                        seek(to: audioTimeClock)
                    }
                }
                selectAudioTrack = false
                selectAudioTrackIndex = 0
                continue
            }
            let size: Int = Int(audioDecoder?.size() ?? 0)
            let packetSize = (videoDecoder?.packetSize() ?? 0)
            let max_packet_buffer_size = 20 * 1024 * 1024
            if size + packetSize >= max_packet_buffer_size {
                let interval = paused ? 0.5 : 0.1
                print("read thread sleep: \(interval)")
                Thread.sleep(forTimeInterval: interval)
                continue
            }
            let result = formatContext?.readFrame(&packet)
            if (result ?? -1) < 0 {
                print("read packet finished")
                endOfFile = true
                videoDecoder?.endOfFile = true
                finished = true
                delegate?.decoderDidEndOfFile(self)
                break
            }
            if packet.stream_index == formatContext?.videoTrack.index {
                print("video: put packet")
                videoDecoder?.putPacket(packet)
                updateBufferedDurationByVideo()
            } else if packet.stream_index == formatContext?.audioTrack.index {
                print("audio: put packet")
                if (audioDecoder?.putPacket(packet) ?? -1) < 0 {
                    error = IRFFCheckErrorCode(result!, IRFFDecoderErrorCode.codecAudioSendPacket.rawValue)
                    delegateErrorCallback()
                    continue
                }
                updateBufferedDurationByAudio()
            }
        }
        reading = false
        checkBufferingStatus()
    }

    private func displayThread() {
        while true {
            if closed || error != nil {
                print("display thread quit")
                break
            }
            if seeking || buffering {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            if paused, let currentFrame = currentVideoFrame {
                videoOutput?.decoder?(self, renderVideoFrame: currentFrame)
                Thread.sleep(forTimeInterval: 0.03)
                continue
            }
            if endOfFile, videoDecoder?.empty() ?? true {
                print("display finished")
                break
            }
            if formatContext?.audioEnable == true {
                let audioTimeClock = self.audioTimeClock
                var sleepTime: TimeInterval = 0
                if let currentFrame = currentVideoFrame {
                    if currentFrame.position >= audioTimeClock {
                        sleepTime = (1.0 / (videoDecoder?.fps ?? 1)) / 2
                    } else if (currentFrame.position + currentFrame.duration) >= audioTimeClock {
                        sleepTime = currentFrame.duration / 2
                    }
                    if sleepTime != 0 {
                        if sleepTime < 0.015 {
                            sleepTime = 0.015
                        }
                        print("display thread sleep: \(sleepTime)")
                        Thread.sleep(forTimeInterval: sleepTime)
                        continue
                    }
                }
                if videoDecoder?.frameEmpty() ?? true {
                    updateBufferedDurationByVideo()
                }
                let newFrame = videoDecoder?.getFrameSync()
                if currentVideoFrame?.position ?? 0 > newFrame?.position ?? 0 {
                    continue
                }
                currentVideoFrame = newFrame
                if let currentFrame = currentVideoFrame {
                    videoOutput?.decoder?(self, renderVideoFrame: currentFrame)
                    updateProgressByVideo()
                    if endOfFile {
                        updateBufferedDurationByVideo()
                    }
                } else if endOfFile {
                    updateBufferedDurationByVideo()
                }
            } else {
                if videoDecoder?.frameEmpty() ?? true {
                    updateBufferedDurationByVideo()
                }
                let newFrame = videoDecoder?.getFrameSync()
                if currentVideoFrame?.position ?? 0 > newFrame?.position ?? 0 {
                    continue
                }
                currentVideoFrame = newFrame
                if let currentFrame = currentVideoFrame {
                    videoOutput?.decoder?(self, renderVideoFrame: currentFrame)
                    updateProgressByVideo()
                    if endOfFile {
                        updateBufferedDurationByVideo()
                    }
                    var sleepTime = currentFrame.duration
                    if sleepTime < 0.0001 {
                        sleepTime = (1.0 / (videoDecoder?.fps ?? 1))
                    }
                    Thread.sleep(forTimeInterval: sleepTime)
                } else if endOfFile {
                    updateBufferedDurationByVideo()
                }
            }
        }
        checkBufferingStatus()
    }

    func pause() {
        paused = true
    }

    func resume() {
        paused = false
        if playbackFinished {
            seek(to: 0)
        }
    }

    func seek(to time: TimeInterval, completeHandler: ((Bool) -> Void)? = nil) {
        guard seekEnable, error == nil else {
            completeHandler?(false)
            return
        }
        let tempDuration: TimeInterval = formatContext?.audioEnable == true ? 8 : 15
        var seekMaxTime = duration - (minBufferedDuration + tempDuration)
        if seekMaxTime < seekMinTime { seekMaxTime = seekMinTime }
        if time > seekMaxTime {
            seekToTime = seekMaxTime
        } else if time < seekMinTime {
            seekToTime = seekMinTime
        } else {
            seekToTime = time
        }
        self.progress = seekToTime
        self.seekCompleteHandler = completeHandler
        self.seeking = true
        videoDecoder?.paused = true
        if endOfFile {
            setupReadPacketOperation()
        }
    }

    func fetchAudioFrame() -> IRFFAudioFrame? {
        if closed || seeking || buffering || paused || playbackFinished || formatContext?.audioEnable != true {
            return nil
        }
        if audioDecoder?.isEmpty() ?? true {
            updateBufferedDurationByAudio()
            return nil
        }
        currentAudioFrame = audioDecoder?.getFrameSync()
        if currentAudioFrame == nil { return nil }
        if endOfFile {
            updateBufferedDurationByAudio()
        }
        updateProgressByAudio()
        audioTimeClock = currentAudioFrame?.position ?? 0
        return currentAudioFrame
    }

    func closeFile() {
        closeFileAsync(true)
    }

    private func closeFileAsync(_ async: Bool) {
        if closed { return }
        closed = true
        videoDecoder?.destroy()
        audioDecoder?.destroy()
        if async {
            DispatchQueue.global().async { [weak self] in
                self?.ffmpegOperationQueue?.cancelAllOperations()
                self?.ffmpegOperationQueue?.waitUntilAllOperationsAreFinished()
                self?.closePropertyValue()
                self?.formatContext?.destroy()
                self?.closeOperation()
            }
        } else {
            ffmpegOperationQueue?.cancelAllOperations()
            ffmpegOperationQueue?.waitUntilAllOperationsAreFinished()
            closePropertyValue()
            formatContext?.destroy()
            closeOperation()
        }
    }

    private func closePropertyValue() {
        seeking = false
        buffering = false
        paused = false
        prepareToDecode = false
        endOfFile = false
        playbackFinished = false
        currentVideoFrame = nil
        currentAudioFrame = nil
        videoDecoder?.paused = false
        videoDecoder?.endOfFile = false
        selectAudioTrack = false
        selectAudioTrackIndex = 0
    }

    private func closeOperation() {
        readPacketOperation = nil
        openFileOperation = nil
        displayOperation = nil
        decodeFrameOperation = nil
        ffmpegOperationQueue = nil
    }

    private func checkBufferingStatus() {
        if buffering {
            if bufferedDuration >= minBufferedDuration || endOfFile {
                buffering = false
            }
        } else if bufferedDuration <= 0.2 && !endOfFile {
            buffering = true
        }
    }

    private func updateBufferedDurationByVideo() {
        if formatContext?.audioEnable == false {
            bufferedDuration = videoDecoder?.duration() ?? 0.0
        }
    }

    private func updateBufferedDurationByAudio() {
        if formatContext?.audioEnable == true {
            bufferedDuration = audioDecoder?.duration() ?? 0.0
        }
    }

    private func updateProgressByVideo() {
        if formatContext?.audioEnable == false && formatContext?.videoEnable == true {
            progress = currentVideoFrame?.position ?? 0
        }
    }

    private func updateProgressByAudio() {
        if formatContext?.audioEnable == true {
            progress = currentAudioFrame?.position ?? 0
        }
    }

    private func delegateErrorCallback() {
        if let error = error {
            delegate?.decoder(self, didError: error)
        }
    }

    deinit {
        closeFileAsync(false)
        print("IRFFDecoder release")
    }
}

// MARK: - Extensions and Utility Functions

extension DispatchQueue {
    private static var onceTracker = [String]()

    class func once(token: String, block: () -> Void) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        if onceTracker.contains(token) {
            return
        }
        onceTracker.append(token)
        block()
    }
}

extension IRFFDecoder: IRFFFormatContextDelegate {
    public func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool {
        return closed
    }
}

extension IRFFDecoder: IRFFAudioDecoderDelegate {
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, samplingRate: inout Float64) {
        samplingRate = audioOutput?.samplingRate ?? 0
    }
    
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, channelCount: inout UInt32) {
        channelCount = audioOutput?.numberOfChannels ?? 0
    }
}

extension IRFFDecoder: IRFFVideoDecoderDelegate {
    func videoDecoderNeedUpdateBufferedDuration(_ videoDecoder: IRFFVideoDecoder) {
        updateBufferedDurationByVideo()
    }

    func videoDecoderNeedCheckBufferingStatus(_ videoDecoder: IRFFVideoDecoder) {
        checkBufferingStatus()
    }

    func videoDecoder(_ videoDecoder: IRFFVideoDecoder, didError error: Error) {
        self.error = error
        delegateErrorCallback()
    }
}
