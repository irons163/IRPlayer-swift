import Foundation
import UIKit

struct IRGLSnapshotDependencies {
    typealias Dispatcher = (@escaping () -> Void) -> Void

    let dispatchToMain: Dispatcher
    let saveImage: (UIImage) -> Void

    static var system: IRGLSnapshotDependencies {
        IRGLSnapshotDependencies(
            dispatchToMain: { operation in
                if Thread.isMainThread {
                    operation()
                } else {
                    DispatchQueue.main.async(execute: operation)
                }
            },
            saveImage: {
                IRPhotoSaver.save($0, toAlbum: "Snapshots")
            }
        )
    }
}

final class IRGLSnapshotSession: @unchecked Sendable {
    struct Diagnostics: Equatable {
        let isClosed: Bool
        let hasPendingRequest: Bool
        let requestCount: Int
        let coalescedRequestCount: Int
        let scheduledCaptureCount: Int
        let savedCaptureCount: Int
        let cancelledCaptureCount: Int
    }

    private struct Ticket: Hashable {
        let epoch: UInt64
        let generation: UInt64
    }

    private let lock = NSLock()
    private let dependencies: IRGLSnapshotDependencies

    private var closed = false
    private var epoch: UInt64 = 0
    private var nextGeneration: UInt64 = 0
    private var pendingTicket: Ticket?
    private var scheduledTickets: Set<Ticket> = []
    private var requestCount = 0
    private var coalescedRequestCount = 0
    private var scheduledCaptureCount = 0
    private var savedCaptureCount = 0
    private var cancelledCaptureCount = 0

    init(dependencies: IRGLSnapshotDependencies = .system) {
        self.dependencies = dependencies
    }

    var diagnostics: Diagnostics {
        lock.lock()
        let snapshot = Diagnostics(
            isClosed: closed,
            hasPendingRequest: pendingTicket != nil,
            requestCount: requestCount,
            coalescedRequestCount: coalescedRequestCount,
            scheduledCaptureCount: scheduledCaptureCount,
            savedCaptureCount: savedCaptureCount,
            cancelledCaptureCount: cancelledCaptureCount
        )
        lock.unlock()
        return snapshot
    }

    var hasPendingRequest: Bool {
        diagnostics.hasPendingRequest
    }

    @discardableResult
    func request() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }

        requestCount += 1
        if pendingTicket != nil {
            coalescedRequestCount += 1
            return true
        }
        nextGeneration &+= 1
        pendingTicket = Ticket(
            epoch: epoch,
            generation: nextGeneration
        )
        return true
    }

    @discardableResult
    func cancelPendingRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pendingTicket != nil else { return false }
        pendingTicket = nil
        cancelledCaptureCount += 1
        return true
    }

    func renderDidComplete(
        capture: @escaping () -> UIImage?
    ) {
        let ticket: Ticket
        lock.lock()
        guard !closed, let pendingTicket else {
            lock.unlock()
            return
        }
        ticket = pendingTicket
        self.pendingTicket = nil
        scheduledTickets.insert(ticket)
        scheduledCaptureCount += 1
        lock.unlock()

        dependencies.dispatchToMain { [weak self] in
            guard let self, self.admit(ticket) else { return }
            guard let image = capture() else { return }
            self.dependencies.saveImage(image)
            self.recordSavedCapture()
        }
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }
        closed = true
        epoch &+= 1
        cancelledCaptureCount += scheduledTickets.count
        if pendingTicket != nil {
            cancelledCaptureCount += 1
        }
        pendingTicket = nil
        scheduledTickets.removeAll(keepingCapacity: false)
        return true
    }

    private func admit(_ ticket: Ticket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed,
              ticket.epoch == epoch,
              scheduledTickets.remove(ticket) != nil else {
            return false
        }
        return true
    }

    private func recordSavedCapture() {
        lock.lock()
        savedCaptureCount += 1
        lock.unlock()
    }
}
