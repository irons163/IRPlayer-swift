import CoreVideo
import Foundation
import VideoToolbox

final class IRFFVideoToolBoxSession<Resource>: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        case settingUp
        case active
        case resetting
        case closing
        case closed
    }

    struct SetupTicket: Equatable {
        fileprivate let generation: UInt64
    }

    private struct Drain {
        fileprivate let generation: UInt64
        fileprivate let terminal: Bool
        let resource: Resource?
    }

    struct Diagnostics: Equatable {
        let phase: Phase
        let generation: UInt64
        let activeLeaseCount: Int
        let hasResource: Bool
    }

    private let condition = NSCondition()
    private var phase: Phase = .idle
    private var generation: UInt64 = 0
    private var resource: Resource?
    private var activeLeaseCount = 0

    var diagnostics: Diagnostics {
        condition.lock()
        defer { condition.unlock() }
        return Diagnostics(
            phase: phase,
            generation: generation,
            activeLeaseCount: activeLeaseCount,
            hasResource: resource != nil
        )
    }

    func beginSetup() -> SetupTicket? {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .idle else { return nil }

        generation &+= 1
        phase = .settingUp
        return SetupTicket(generation: generation)
    }

    func install(_ resource: Resource, for ticket: SetupTicket) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .settingUp,
              generation == ticket.generation else {
            return false
        }

        self.resource = resource
        phase = .active
        condition.broadcast()
        return true
    }

    func cancelSetup(_ ticket: SetupTicket) {
        condition.lock()
        defer { condition.unlock() }
        guard phase == .settingUp,
              generation == ticket.generation else {
            return
        }

        phase = .idle
        condition.broadcast()
    }

    func withResource<Result>(
        default defaultValue: Result,
        _ body: (Resource) -> Result
    ) -> Result {
        condition.lock()
        guard phase == .active, let resource else {
            condition.unlock()
            return defaultValue
        }
        activeLeaseCount += 1
        condition.unlock()

        defer {
            condition.lock()
            activeLeaseCount -= 1
            if activeLeaseCount == 0 {
                condition.broadcast()
            }
            condition.unlock()
        }
        return body(resource)
    }

    @discardableResult
    func reset(_ tearDown: (Resource) -> Void) -> Bool {
        drain(terminal: false, tearDown: tearDown)
    }

    @discardableResult
    func close(_ tearDown: (Resource) -> Void) -> Bool {
        drain(terminal: true, tearDown: tearDown)
    }

    private func drain(
        terminal: Bool,
        tearDown: (Resource) -> Void
    ) -> Bool {
        guard let drain = beginDrain(terminal: terminal) else {
            return false
        }
        if let resource = drain.resource {
            tearDown(resource)
        }
        finish(drain)
        return true
    }

    private func finish(_ drain: Drain) {
        condition.lock()
        defer { condition.unlock() }
        guard generation == drain.generation else { return }

        if drain.terminal {
            guard phase == .closing else { return }
            phase = .closed
        } else {
            guard phase == .resetting else { return }
            phase = .idle
        }
        condition.broadcast()
    }

    private func beginDrain(terminal: Bool) -> Drain? {
        condition.lock()
        defer { condition.unlock() }

        if terminal {
            while phase == .resetting {
                condition.wait()
            }
            if phase == .closing {
                while phase == .closing {
                    condition.wait()
                }
                return nil
            }
            guard phase != .closed else { return nil }
            phase = .closing
        } else {
            guard phase != .resetting,
                  phase != .closing,
                  phase != .closed else {
                return nil
            }
            phase = .resetting
        }

        generation &+= 1
        while activeLeaseCount > 0 {
            condition.wait()
        }

        let drainedResource = resource
        resource = nil
        return Drain(
            generation: generation,
            terminal: terminal,
            resource: drainedResource
        )
    }
}

final class IRFFVideoToolBoxCallbackState: @unchecked Sendable {
    struct Snapshot {
        let status: OSStatus
        let imageBuffer: CVImageBuffer?
    }

    private let lock = NSLock()
    private var status: OSStatus = noErr
    private var imageBuffer: CVImageBuffer?

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(status: status, imageBuffer: imageBuffer)
    }

    func reset() {
        lock.lock()
        status = noErr
        imageBuffer = nil
        lock.unlock()
    }

    func publish(status: OSStatus, imageBuffer: CVImageBuffer?) {
        lock.lock()
        self.status = status
        self.imageBuffer = imageBuffer
        lock.unlock()
    }
}
