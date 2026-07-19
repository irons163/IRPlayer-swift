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
    static var subsystem = Bundle.main.bundleIdentifier ?? "IRPlayerImp"

    /// Set this delegate to receive all IRPlayer log messages in your own
    /// logging system. Setting it to `nil` restores OSLog output.
    nonisolated(unsafe) static weak var delegate: (any IRPlayerLoggerDelegate)?

    static var libraryLogger = IRPlayerLogger(subsystem: subsystem, category: "library")
}

/// Forwards messages to `IRPlayerImp.Logger.delegate` when one is set and falls
/// back to OSLog otherwise.
public struct IRPlayerLogger {
    private let osLogger: Logger
    private let category: String

    public init(subsystem: String, category: String) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
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
        if let delegate = IRPlayerImp.Logger.delegate {
            delegate.irPlayer(didLog: message, level: level, category: category)
            return
        }

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
