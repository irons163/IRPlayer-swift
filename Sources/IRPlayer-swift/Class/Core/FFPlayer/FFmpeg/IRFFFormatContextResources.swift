import CoreGraphics
import Foundation
import IRFFMpeg

final class IRFFFormatContextInterruptState: @unchecked Sendable {
    struct Diagnostics: Equatable {
        let closeRequested: Bool
        let hasContext: Bool
        let hasDelegate: Bool
    }

    private let lock = NSLock()
    private weak var context: IRFFFormatContext?
    private weak var delegate: IRFFFormatContextDelegate?
    private var closeRequested = false

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            closeRequested: closeRequested,
            hasContext: context != nil,
            hasDelegate: delegate != nil
        )
    }

    var currentDelegate: IRFFFormatContextDelegate? {
        lock.lock()
        defer { lock.unlock() }
        return delegate
    }

    func bind(context: IRFFFormatContext) {
        lock.lock()
        self.context = context
        lock.unlock()
    }

    func setDelegate(_ delegate: IRFFFormatContextDelegate?) {
        lock.lock()
        self.delegate = delegate
        lock.unlock()
    }

    func prepareForSetup() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closeRequested
    }

    func requestClose() {
        lock.lock()
        closeRequested = true
        lock.unlock()
    }

    func shouldInterrupt() -> Bool {
        lock.lock()
        let closeRequested = closeRequested
        let context = context
        let delegate = delegate
        lock.unlock()

        if closeRequested {
            return true
        }
        guard let context else {
            return true
        }
        return delegate?.formatContextNeedInterrupt(context) == true
    }

    func makeRetainedCallbackReference() -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
    }

    static func releaseRetainedCallbackReference(
        _ reference: UnsafeMutableRawPointer
    ) {
        Unmanaged<IRFFFormatContextInterruptState>
            .fromOpaque(reference)
            .release()
    }
}

struct IRFFFormatContextResourceRuntime {
    let freeCodecContext: (
        inout UnsafeMutablePointer<AVCodecContext>?
    ) -> Void
    let closeInputContext: (
        inout UnsafeMutablePointer<AVFormatContext>?
    ) -> Void
    let releaseCallbackReference: (UnsafeMutableRawPointer) -> Void

    static let live = IRFFFormatContextResourceRuntime(
        freeCodecContext: { context in
            avcodec_free_context(&context)
        },
        closeInputContext: { context in
            avformat_close_input(&context)
        },
        releaseCallbackReference: {
            IRFFFormatContextInterruptState
                .releaseRetainedCallbackReference($0)
        }
    )
}

final class IRFFFormatContextGeneration: @unchecked Sendable {
    struct Diagnostics: Equatable {
        let isClosed: Bool
        let hasFormatContext: Bool
        let hasVideoCodecContext: Bool
        let hasAudioCodecContext: Bool
        let hasCallbackReference: Bool
    }

    private let closeLock = NSLock()
    private let runtime: IRFFFormatContextResourceRuntime
    private var isClosed = false
    private var callbackReference: UnsafeMutableRawPointer?

    private(set) var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private(set) var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    private(set) var audioCodecContext: UnsafeMutablePointer<AVCodecContext>?

    var metadata: [AnyHashable: Any] = [:]
    var videoTrack: IRFFTrack?
    var audioTrack: IRFFTrack?
    var videoTracks: [IRFFTrack] = []
    var audioTracks: [IRFFTrack] = []
    var videoTimebase: TimeInterval = 0
    var videoFPS: TimeInterval = 0
    var videoPresentationSize: CGSize = .zero
    var videoAspect: CGFloat = 0
    var audioTimebase: TimeInterval = 0

    var diagnostics: Diagnostics {
        closeLock.lock()
        defer { closeLock.unlock() }
        return Diagnostics(
            isClosed: isClosed,
            hasFormatContext: formatContext != nil,
            hasVideoCodecContext: videoCodecContext != nil,
            hasAudioCodecContext: audioCodecContext != nil,
            hasCallbackReference: callbackReference != nil
        )
    }

    init(
        formatContext: UnsafeMutablePointer<AVFormatContext>,
        callbackReference: UnsafeMutableRawPointer,
        runtime: IRFFFormatContextResourceRuntime = .live
    ) {
        self.formatContext = formatContext
        self.callbackReference = callbackReference
        self.runtime = runtime
    }

    func installVideoCodecContext(
        _ context: UnsafeMutablePointer<AVCodecContext>
    ) {
        closeLock.lock()
        precondition(!isClosed && videoCodecContext == nil)
        videoCodecContext = context
        closeLock.unlock()
    }

    func installAudioCodecContext(
        _ context: UnsafeMutablePointer<AVCodecContext>
    ) {
        closeLock.lock()
        precondition(!isClosed && audioCodecContext == nil)
        audioCodecContext = context
        closeLock.unlock()
    }

    func replaceAudioCodecContext(
        with context: UnsafeMutablePointer<AVCodecContext>
    ) {
        closeLock.lock()
        defer { closeLock.unlock() }
        precondition(!isClosed)
        var replacedContext = audioCodecContext
        audioCodecContext = context
        runtime.freeCodecContext(&replacedContext)
    }

    func destroyAudioTrack() {
        closeLock.lock()
        defer { closeLock.unlock() }
        var context = audioCodecContext
        audioCodecContext = nil
        audioTrack = nil
        audioTracks = []
        audioTimebase = 0
        runtime.freeCodecContext(&context)
    }

    func destroyVideoTrack() {
        closeLock.lock()
        defer { closeLock.unlock() }
        var context = videoCodecContext
        videoCodecContext = nil
        videoTrack = nil
        videoTracks = []
        videoTimebase = 0
        videoFPS = 0
        videoPresentationSize = .zero
        videoAspect = 0
        runtime.freeCodecContext(&context)
    }

    @discardableResult
    func close() -> Bool {
        closeLock.lock()
        guard !isClosed else {
            closeLock.unlock()
            return false
        }

        isClosed = true
        var videoCodecContext = videoCodecContext
        self.videoCodecContext = nil
        var audioCodecContext = audioCodecContext
        self.audioCodecContext = nil
        var formatContext = formatContext
        self.formatContext = nil
        let callbackReference = callbackReference
        self.callbackReference = nil

        runtime.freeCodecContext(&videoCodecContext)
        runtime.freeCodecContext(&audioCodecContext)
        runtime.closeInputContext(&formatContext)
        if let callbackReference {
            runtime.releaseCallbackReference(callbackReference)
        }
        closeLock.unlock()
        return true
    }

    deinit {
        close()
    }
}
