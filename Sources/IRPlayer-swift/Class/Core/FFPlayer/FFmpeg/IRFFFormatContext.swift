//
//  IRFFFormatContext.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/12.
//

import CoreGraphics
import Foundation
import IRFFMpeg
import IRPlayerObjc

public protocol IRFFFormatContextDelegate: AnyObject {
    func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool
}

public final class IRFFFormatContext: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        case opening
        case active
        case failed
        case closing
        case closed
    }

    enum AudioTrackSelectionAction: Equatable {
        case noChange
        case select
    }

    struct AudioTrackSelectionResult {
        let error: NSError?
        let didChangeTrack: Bool
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let hasGeneration: Bool
        let hasFormatContext: Bool
        let hasVideoCodecContext: Bool
        let hasAudioCodecContext: Bool
        let interruptCloseRequested: Bool
    }

    private let contentURL: URL
    private let videoFormat: IRVideoFormat
    private let operationLock = NSLock()
    private let interruptState = IRFFFormatContextInterruptState()

    private var phase: Phase = .idle
    private var generation: IRFFFormatContextGeneration?
    private var storedError: NSError?

    var delegate: IRFFFormatContextDelegate? {
        get { interruptState.currentDelegate }
        set { interruptState.setDelegate(newValue) }
    }

    var diagnostics: Diagnostics {
        withOperation {
            let resourceDiagnostics = generation?.diagnostics
            return Diagnostics(
                phase: phase,
                hasGeneration: generation != nil,
                hasFormatContext:
                    resourceDiagnostics?.hasFormatContext == true,
                hasVideoCodecContext:
                    resourceDiagnostics?.hasVideoCodecContext == true,
                hasAudioCodecContext:
                    resourceDiagnostics?.hasAudioCodecContext == true,
                interruptCloseRequested:
                    interruptState.diagnostics.closeRequested
            )
        }
    }

    var error: NSError? {
        withOperation { storedError }
    }

    var metadata: [AnyHashable: Any] {
        withGeneration(default: [:]) { $0.metadata }
    }

    var bitrate: TimeInterval {
        withGeneration(default: 0) { generation in
            guard let formatContext = generation.formatContext else {
                return 0
            }
            return Self.bitrateKbps(
                from: formatContext.pointee.bit_rate
            )
        }
    }

    var duration: TimeInterval {
        withGeneration(default: 0) { generation in
            guard let formatContext = generation.formatContext else {
                return 0
            }
            return Self.durationSeconds(
                from: formatContext.pointee.duration
            )
        }
    }

    var videoEnable: Bool {
        withGeneration(default: false) {
            $0.videoCodecContext != nil
        }
    }

    var audioEnable: Bool {
        withGeneration(default: false) {
            $0.audioCodecContext != nil
        }
    }

    var videoTrack: IRFFTrack? {
        withGeneration(default: nil) { $0.videoTrack }
    }

    var audioTrack: IRFFTrack? {
        withGeneration(default: nil) { $0.audioTrack }
    }

    var videoTracks: [IRFFTrack] {
        withGeneration(default: []) { $0.videoTracks }
    }

    var audioTracks: [IRFFTrack] {
        withGeneration(default: []) { $0.audioTracks }
    }

    var videoTimebase: TimeInterval {
        withGeneration(default: 0) { $0.videoTimebase }
    }

    var videoFPS: TimeInterval {
        withGeneration(default: 0) { $0.videoFPS }
    }

    var videoPresentationSize: CGSize {
        withGeneration(default: .zero) {
            $0.videoPresentationSize
        }
    }

    var videoAspect: CGFloat {
        withGeneration(default: 0) { $0.videoAspect }
    }

    var audioTimebase: TimeInterval {
        withGeneration(default: 0) { $0.audioTimebase }
    }

    var videoCodecContext: UnsafeMutablePointer<AVCodecContext>? {
        withGeneration(default: nil) { $0.videoCodecContext }
    }

    var audioCodecContext: UnsafeMutablePointer<AVCodecContext>? {
        withGeneration(default: nil) { $0.audioCodecContext }
    }

    init(contentURL: URL, videoFormat: IRVideoFormat) {
        self.contentURL = contentURL
        self.videoFormat = videoFormat
        interruptState.bind(context: self)
    }

    func setupSync() {
        withOperation {
            guard phase == .idle,
                  interruptState.prepareForSetup() else {
                return
            }

            phase = .opening
            storedError = nil
            switch IRFFFormatContextBuilder.makeGeneration(
                contentURL: contentURL,
                videoFormat: videoFormat,
                interruptState: interruptState
            ) {
            case let .success(generation):
                self.generation = generation
                phase = .active
            case let .failure(error):
                storedError = error
                phase = .failed
            }
        }
    }

    func seekFile(withFFTimebase time: TimeInterval) {
        guard let timestamp = Self.seekTimestamp(for: time) else {
            return
        }
        withOperation {
            guard phase == .active,
                  let formatContext = generation?.formatContext else {
                return
            }
            av_seek_frame(
                formatContext,
                -1,
                timestamp,
                AVSEEK_FLAG_BACKWARD
            )
        }
    }

    func readFrame(_ packet: UnsafeMutablePointer<AVPacket>) -> Int32 {
        withOperation {
            guard phase == .active,
                  let formatContext = generation?.formatContext else {
                return -1
            }
            return av_read_frame(formatContext, packet)
        }
    }

    func containAudioTrack(_ audioTrackIndex: Int) -> Bool {
        withGeneration(default: false) { generation in
            generation.audioTracks.contains {
                $0.index == audioTrackIndex
            }
        }
    }

    func selectAudioTrackIndexResult(
        _ audioTrackIndex: Int
    ) -> AudioTrackSelectionResult {
        withOperation {
            guard phase == .active, let generation else {
                return AudioTrackSelectionResult(
                    error: nil,
                    didChangeTrack: false
                )
            }

            let containsRequestedTrack = generation.audioTracks.contains {
                $0.index == audioTrackIndex
            }
            guard Self.audioTrackSelectionAction(
                requestedIndex: audioTrackIndex,
                currentIndex: generation.audioTrack?.index,
                containsRequestedTrack: containsRequestedTrack
            ) == .select else {
                return AudioTrackSelectionResult(
                    error: nil,
                    didChangeTrack: false
                )
            }

            let candidate = IRFFFormatContextBuilder.makeCodecContext(
                trackIndex: audioTrackIndex,
                in: generation.formatContext,
                domain: "audio select"
            )
            switch candidate {
            case let .success(codecContext):
                generation.replaceAudioCodecContext(
                    with: codecContext
                )
                generation.audioTrack = generation.audioTracks.first {
                    $0.index == audioTrackIndex
                }
                if let stream = Self.stream(
                    at: audioTrackIndex,
                    in: generation.formatContext
                ) {
                    generation.audioTimebase = IRFFStreamGetTimebase(
                        stream,
                        defaultTimebase: 0.000025
                    )
                }
                return AudioTrackSelectionResult(
                    error: nil,
                    didChangeTrack: true
                )
            case let .failure(error):
                IRFFRuntimeDebugOutput.write(
                    "select audio track error: \(error)"
                )
                return AudioTrackSelectionResult(
                    error: error,
                    didChangeTrack: false
                )
            }
        }
    }

    func selectAudioTrackIndex(_ audioTrackIndex: Int) -> NSError? {
        selectAudioTrackIndexResult(audioTrackIndex).error
    }

    var contentURLString: String {
        contentURL.isFileURL
            ? contentURL.path
            : contentURL.absoluteString
    }

    func destroyAudioTrack() {
        withOperation {
            guard phase == .active else { return }
            generation?.destroyAudioTrack()
        }
    }

    func destroyVideoTrack() {
        withOperation {
            guard phase == .active else { return }
            generation?.destroyVideoTrack()
        }
    }

    func destroy() {
        interruptState.requestClose()
        withOperation {
            guard phase != .closing, phase != .closed else {
                return
            }

            phase = .closing
            let generation = generation
            self.generation = nil
            generation?.close()
            phase = .closed
        }
    }

    private func withGeneration<Result>(
        default defaultValue: Result,
        _ body: (IRFFFormatContextGeneration) -> Result
    ) -> Result {
        withOperation {
            guard phase == .active, let generation else {
                return defaultValue
            }
            return body(generation)
        }
    }

    private func withOperation<Result>(
        _ body: () throws -> Result
    ) rethrows -> Result {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try body()
    }

    deinit {
        destroy()
    }
}

func ffmpeg_interrupt_callback(
    ctx: UnsafeMutableRawPointer?
) -> Int32 {
    guard let ctx else { return 0 }
    let interruptState =
        Unmanaged<IRFFFormatContextInterruptState>
            .fromOpaque(ctx)
            .takeUnretainedValue()
    return interruptState.shouldInterrupt() ? 1 : 0
}
