import Foundation
import IRFFMpeg

struct IRFFDecodeFrameRuntime {
    let allocateFrame:
        () -> UnsafeMutablePointer<AVFrame>?
    let freeFrame: (
        inout UnsafeMutablePointer<AVFrame>?
    ) -> Void

    static let live = IRFFDecodeFrameRuntime(
        allocateFrame: {
            av_frame_alloc()
        },
        freeFrame: { frame in
            av_frame_free(&frame)
        }
    )
}

final class IRFFDecodeFrame: @unchecked Sendable {
    struct Diagnostics: Equatable {
        let closed: Bool
        let hasFrame: Bool
    }

    private let lock = NSLock()
    private let runtime: IRFFDecodeFrameRuntime
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var closed = false

    init?(
        runtime: IRFFDecodeFrameRuntime = .live
    ) {
        guard let frame = runtime.allocateFrame() else {
            return nil
        }
        self.runtime = runtime
        self.frame = frame
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            closed: closed,
            hasFrame: frame != nil
        )
    }

    @discardableResult
    func withFrame(
        _ body: (
            UnsafeMutablePointer<AVFrame>
        ) -> Bool
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let frame else {
            return false
        }
        return body(frame)
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }

        runtime.freeFrame(&frame)
        closed = true
        return true
    }

    deinit {
        close()
    }
}
