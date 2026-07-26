import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
#else
@_implementationOnly import IRFFMpeg
#endif

struct IRFFPacketRuntime {
    let moveReference: (
        inout AVPacket,
        inout AVPacket
    ) -> Void
    let unreference: (inout AVPacket) -> Void

    static let live = IRFFPacketRuntime(
        moveReference: { destination, source in
            av_packet_move_ref(
                &destination,
                &source
            )
        },
        unreference: { packet in
            av_packet_unref(&packet)
        }
    )
}

final class IRFFPacket: @unchecked Sendable {
    enum Phase: Equatable {
        case empty
        case ready
        case closed
    }

    struct Snapshot: Equatable {
        let streamIndex: Int32
        let size: Int32
        let duration: Int64
        let presentationTimestamp: Int64
        let decodeTimestamp: Int64
        let hasData: Bool
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let hasData: Bool
    }

    private let lock = NSLock()
    private let runtime: IRFFPacketRuntime
    private var packet = AVPacket()
    private var phase: Phase = .empty

    init(runtime: IRFFPacketRuntime = .live) {
        self.runtime = runtime
    }

    init(
        consuming source: inout AVPacket,
        runtime: IRFFPacketRuntime = .live
    ) {
        self.runtime = runtime
        runtime.moveReference(
            &packet,
            &source
        )
        phase = .ready
    }

    var snapshot: Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .ready else { return nil }
        return Snapshot(
            streamIndex: packet.stream_index,
            size: packet.size,
            duration: packet.duration,
            presentationTimestamp: packet.pts,
            decodeTimestamp: packet.dts,
            hasData: packet.data != nil
        )
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            phase: phase,
            hasData: packet.data != nil
        )
    }

    @discardableResult
    func fill(
        _ body: (inout AVPacket) -> Int32
    ) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .empty else { return -1 }

        let result = body(&packet)
        if result >= 0 {
            phase = .ready
        } else {
            runtime.unreference(&packet)
            phase = .closed
        }
        return result
    }

    @discardableResult
    func withPacket(
        _ body: (AVPacket) -> Bool
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .ready else { return false }
        return body(packet)
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard phase != .closed else { return false }

        runtime.unreference(&packet)
        phase = .closed
        return true
    }

    deinit {
        close()
    }
}
