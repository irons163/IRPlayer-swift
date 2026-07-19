import Foundation

final class IRPlaybackBackendCoordinator {
    typealias Factory = (IRPlaybackBackendKind) -> (any IRPlaybackBackend)?

    private let factory: Factory
    private var backends: [IRPlaybackBackendKind: any IRPlaybackBackend] = [:]

    private(set) var activeKind: IRPlaybackBackendKind?

    init(factory: @escaping Factory) {
        self.factory = factory
    }

    var snapshot: IRPlaybackBackendSnapshot {
        activeBackend?.snapshot ?? .empty
    }

    var activeBackend: (any IRPlaybackBackend)? {
        guard let activeKind else { return nil }
        return backends[activeKind]
    }

    @discardableResult
    func replace(with kind: IRPlaybackBackendKind?) -> (any IRPlaybackBackend)? {
        activeKind = nil

        guard let kind else {
            stopAllBackends()
            return nil
        }

        stopBackends(except: kind)
        guard let backend = backend(for: kind) else { return nil }
        activeKind = kind
        backend.replaceVideo()
        return backend
    }

    func play() {
        activeBackend?.play()
    }

    func pause() {
        activeBackend?.pause()
    }

    func seek(to time: TimeInterval, completionHandler: ((Bool) -> Void)? = nil) {
        activeBackend?.seek(to: time, completionHandler: completionHandler)
    }

    func reloadVolume() {
        backends.values.forEach { $0.reloadVolume() }
    }

    func reloadPlayableBufferInterval() {
        backends.values.forEach { $0.reloadPlayableBufferInterval() }
    }

    func reset() {
        activeKind = nil
        stopAllBackends()
        backends.removeAll(keepingCapacity: false)
    }

    func hasBackend(for kind: IRPlaybackBackendKind) -> Bool {
        backends[kind] != nil
    }

    func existingBackend(for kind: IRPlaybackBackendKind) -> (any IRPlaybackBackend)? {
        backends[kind]
    }

    private func backend(for kind: IRPlaybackBackendKind) -> (any IRPlaybackBackend)? {
        if let backend = backends[kind] {
            return backend
        }

        guard let backend = factory(kind), backend.kind == kind else { return nil }
        backends[kind] = backend
        return backend
    }

    private func stopBackends(except retainedKind: IRPlaybackBackendKind) {
        for (kind, backend) in backends where kind != retainedKind {
            backend.stop()
        }
    }

    private func stopAllBackends() {
        backends.values.forEach { $0.stop() }
    }
}
