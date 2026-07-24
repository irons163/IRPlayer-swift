import Foundation
import OSLog

/// Severity levels that mirror OSLog's level hierarchy.
@objc public enum IRPlayerLogLevel: Int, Equatable, Hashable, Sendable {
    case debug
    case info
    case warning
    case error
}

/// Implement this protocol to intercept IRPlayer log messages and forward them
/// to your own logging system. When a delegate is set it receives all log
/// messages instead of the built-in OSLog output.
public protocol IRPlayerLoggerDelegate: AnyObject {
    func irPlayer(didLog message: String, level: IRPlayerLogLevel, category: String)
}

public extension IRPlayerImp { enum Logger {} }

public extension IRPlayerImp.Logger {
    static var subsystem: String {
        get {
            IRPlayerLoggingRuntime.systemSession.subsystem
        }
        set {
            IRPlayerLoggingRuntime.systemSession
                .replaceSubsystem(newValue)
        }
    }

    /// Set this delegate to receive all IRPlayer log messages in your own
    /// logging system. Setting it to `nil` restores OSLog output.
    static var delegate: (any IRPlayerLoggerDelegate)? {
        get {
            IRPlayerLoggingRuntime.systemSession.delegate
        }
        set {
            IRPlayerLoggingRuntime.systemSession.delegate =
                newValue
        }
    }

    static var libraryLogger: IRPlayerLogger {
        get {
            IRPlayerLoggingRuntime.systemSession
                .libraryLogger
        }
        set {
            IRPlayerLoggingRuntime.systemSession
                .libraryLogger = newValue
        }
    }
}

/// Forwards messages to `IRPlayerImp.Logger.delegate` when one is set and falls
/// back to OSLog otherwise.
public struct IRPlayerLogger: @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        let subsystem: String
        let category: String
    }

    private let osLogger: Logger
    let configuration: Configuration
    private let sessionReference:
        IRPlayerLoggingSessionReference

    public init(subsystem: String, category: String) {
        self.init(
            subsystem: subsystem,
            category: category,
            session: IRPlayerLoggingRuntime.systemSession
        )
    }

    init(
        subsystem: String,
        category: String,
        session: IRPlayerLoggingSession
    ) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        configuration = Configuration(
            subsystem: subsystem,
            category: category
        )
        sessionReference =
            IRPlayerLoggingSessionReference(session)
    }

    public func debug(_ message: @autoclosure () -> String) {
        emit(message(), level: .debug)
    }

    public func info(_ message: @autoclosure () -> String) {
        emit(message(), level: .info)
    }

    public func warning(_ message: @autoclosure () -> String) {
        emit(message(), level: .warning)
    }

    public func error(_ message: @autoclosure () -> String) {
        emit(message(), level: .error)
    }

    private func emit(_ message: String, level: IRPlayerLogLevel) {
        guard let session = sessionReference.session else {
            writeToOSLog(message, level: level)
            return
        }

        _ = session.emit(
            message,
            level: level,
            category: configuration.category
        ) {
            writeToOSLog(message, level: level)
        }
    }

    func bound(
        to session: IRPlayerLoggingSession
    ) -> IRPlayerLogger {
        IRPlayerLogger(
            subsystem: configuration.subsystem,
            category: configuration.category,
            session: session
        )
    }

    private func writeToOSLog(
        _ message: String,
        level: IRPlayerLogLevel
    ) {
        switch level {
        case .debug:
            osLogger.debug("\(message)")
        case .info:
            osLogger.info("\(message)")
        case .warning:
            osLogger.warning("\(message)")
        case .error:
            osLogger.error("\(message)")
        }
    }
}

private final class IRPlayerLoggingSessionReference:
    @unchecked Sendable
{
    weak var session: IRPlayerLoggingSession?

    init(_ session: IRPlayerLoggingSession) {
        self.session = session
    }
}
