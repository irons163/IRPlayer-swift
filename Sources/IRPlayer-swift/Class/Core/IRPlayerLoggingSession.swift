//
//  IRPlayerLoggingSession.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation

final class IRPlayerLoggingSession: @unchecked Sendable {
    enum Phase: Equatable, Sendable {
        case active
        case closed
    }

    struct Diagnostics: Equatable, Sendable {
        let phase: Phase
        let subsystem: String
        let libraryLoggerSubsystem: String
        let libraryLoggerCategory: String
        let hasDelegate: Bool
        let configurationGeneration: UInt64
        let delegateGeneration: UInt64
        let activeDeliveryCount: Int
        let emissionCount: Int
        let completedDeliveryCount: Int
        let delegateDeliveryCount: Int
        let fallbackDeliveryCount: Int
        let rejectedEmissionCount: Int
        let rejectedMutationCount: Int
        let closeCount: Int
    }

    private let lock = NSLock()

    private var phase: Phase = .active
    private var subsystemStorage: String
    private var libraryLoggerStorage: IRPlayerLogger?
    private weak var delegateStorage:
        (any IRPlayerLoggerDelegate)?
    private var configurationGeneration: UInt64 = 1
    private var delegateGeneration: UInt64 = 0
    private var activeDeliveryCount = 0
    private var emissionCount = 0
    private var completedDeliveryCount = 0
    private var delegateDeliveryCount = 0
    private var fallbackDeliveryCount = 0
    private var rejectedEmissionCount = 0
    private var rejectedMutationCount = 0
    private var closeCount = 0

    init(subsystem: String) {
        let subsystem = Self.normalizedSubsystem(subsystem)
        subsystemStorage = subsystem
        libraryLoggerStorage = nil
        libraryLoggerStorage = IRPlayerLogger(
            subsystem: subsystem,
            category: "library",
            session: self
        )
    }

    var subsystem: String {
        lock.lock()
        defer { lock.unlock() }
        return subsystemStorage
    }

    var delegate: (any IRPlayerLoggerDelegate)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            guard phase == .active else { return nil }
            return delegateStorage
        }
        set {
            _ = replaceDelegate(newValue)
        }
    }

    var libraryLogger: IRPlayerLogger {
        get {
            lock.lock()
            defer { lock.unlock() }
            return resolvedLibraryLoggerLocked()
        }
        set {
            _ = replaceLibraryLogger(newValue)
        }
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        let logger = resolvedLibraryLoggerLocked()
        return Diagnostics(
            phase: phase,
            subsystem: subsystemStorage,
            libraryLoggerSubsystem:
                logger.configuration.subsystem,
            libraryLoggerCategory:
                logger.configuration.category,
            hasDelegate: delegateStorage != nil,
            configurationGeneration:
                configurationGeneration,
            delegateGeneration: delegateGeneration,
            activeDeliveryCount: activeDeliveryCount,
            emissionCount: emissionCount,
            completedDeliveryCount:
                completedDeliveryCount,
            delegateDeliveryCount:
                delegateDeliveryCount,
            fallbackDeliveryCount:
                fallbackDeliveryCount,
            rejectedEmissionCount:
                rejectedEmissionCount,
            rejectedMutationCount:
                rejectedMutationCount,
            closeCount: closeCount
        )
    }

    @discardableResult
    func replaceSubsystem(
        _ subsystem: String
    ) -> Bool {
        let subsystem =
            Self.normalizedSubsystem(subsystem)
        let logger = IRPlayerLogger(
            subsystem: subsystem,
            category: "library",
            session: self
        )

        lock.lock()
        guard phase == .active else {
            rejectedMutationCount += 1
            lock.unlock()
            return false
        }
        subsystemStorage = subsystem
        libraryLoggerStorage = logger
        configurationGeneration &+= 1
        lock.unlock()
        return true
    }

    @discardableResult
    func replaceLibraryLogger(
        _ logger: IRPlayerLogger
    ) -> Bool {
        let logger = logger.bound(to: self)

        lock.lock()
        guard phase == .active else {
            rejectedMutationCount += 1
            lock.unlock()
            return false
        }
        libraryLoggerStorage = logger
        configurationGeneration &+= 1
        lock.unlock()
        return true
    }

    @discardableResult
    func replaceDelegate(
        _ delegate: (any IRPlayerLoggerDelegate)?
    ) -> Bool {
        lock.lock()
        guard phase == .active else {
            rejectedMutationCount += 1
            lock.unlock()
            return false
        }
        delegateStorage = delegate
        delegateGeneration &+= 1
        lock.unlock()
        return true
    }

    @discardableResult
    func emit(
        _ message: String,
        level: IRPlayerLogLevel,
        category: String,
        fallback: () -> Void
    ) -> Bool {
        let delegate: (any IRPlayerLoggerDelegate)?

        lock.lock()
        guard phase == .active else {
            rejectedEmissionCount += 1
            lock.unlock()
            return false
        }
        delegate = delegateStorage
        activeDeliveryCount += 1
        emissionCount += 1
        if delegate == nil {
            fallbackDeliveryCount += 1
        } else {
            delegateDeliveryCount += 1
        }
        lock.unlock()

        if let delegate {
            delegate.irPlayer(
                didLog: message,
                level: level,
                category: category
            )
        } else {
            fallback()
        }

        lock.lock()
        activeDeliveryCount -= 1
        completedDeliveryCount += 1
        lock.unlock()
        return true
    }

    @discardableResult
    func close() -> Bool {
        invalidate(recordClose: true)
    }

    deinit {
        _ = invalidate(recordClose: false)
    }

    private func resolvedLibraryLoggerLocked()
        -> IRPlayerLogger
    {
        if let libraryLoggerStorage {
            return libraryLoggerStorage
        }
        return IRPlayerLogger(
            subsystem: subsystemStorage,
            category: "library",
            session: self
        )
    }

    private func invalidate(
        recordClose: Bool
    ) -> Bool {
        lock.lock()
        guard phase == .active else {
            lock.unlock()
            return false
        }
        phase = .closed
        delegateStorage = nil
        delegateGeneration &+= 1
        if recordClose {
            closeCount += 1
        }
        lock.unlock()
        return true
    }

    private static func normalizedSubsystem(
        _ subsystem: String
    ) -> String {
        let subsystem = subsystem.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return subsystem.isEmpty
            ? "IRPlayerImp"
            : subsystem
    }
}

enum IRPlayerLoggingRuntime {
    static let systemSession = IRPlayerLoggingSession(
        subsystem:
            Bundle.main.bundleIdentifier ?? "IRPlayerImp"
    )
}
