import Foundation

final class IRAVPlayerPresentationLoop:
    @unchecked Sendable
{
    enum Phase:
        Equatable,
        Hashable,
        Sendable
    {
        case uninstalled
        case idle
        case active
        case closed
    }

    struct Token:
        Equatable,
        Hashable,
        Sendable
    {
        fileprivate let generation: UInt64
    }

    struct Tick:
        Equatable,
        Hashable,
        Sendable
    {
        let presentationToken: Token
        let sessionToken: IRAVPlayerSession.Token
        let timestamp: TimeInterval
    }

    struct Diagnostics:
        Equatable,
        Sendable
    {
        let phase: Phase
        let generation: UInt64
        let activePresentationToken: Token?
        let hasActiveSessionToken: Bool
        let driver: IRDisplayLinkSnapshot
        let installationCount: Int
        let activationCount: Int
        let deactivationCount: Int
        let deliveredTickCount: Int
        let rejectedTickCount: Int
        let closeCount: Int
    }

    typealias TickHandler = (Tick) -> Void

    private let mutationLock = NSLock()
    private let stateLock = NSLock()
    private let driver: any IRDisplayLinkDriving
    private var phase: Phase = .uninstalled
    private var generationCounter: UInt64 = 0
    private var activePresentationToken: Token?
    private var activeSessionToken:
        IRAVPlayerSession.Token?
    private var tickHandler: TickHandler?
    private var installationCount = 0
    private var activationCount = 0
    private var deactivationCount = 0
    private var deliveredTickCount = 0
    private var rejectedTickCount = 0
    private var closeCount = 0

    init(driver: any IRDisplayLinkDriving) {
        self.driver = driver
    }

    static func system()
        -> IRAVPlayerPresentationLoop
    {
        IRAVPlayerPresentationLoop(
            driver: IRSystemDisplayLinkDriver()
        )
    }

    var diagnostics: Diagnostics {
        mutationLock.lock()
        stateLock.lock()
        let state = (
            phase,
            generationCounter,
            activePresentationToken,
            activeSessionToken != nil,
            installationCount,
            activationCount,
            deactivationCount,
            deliveredTickCount,
            rejectedTickCount,
            closeCount
        )
        stateLock.unlock()
        let driverSnapshot = driver.snapshot
        mutationLock.unlock()

        return Diagnostics(
            phase: state.0,
            generation: state.1,
            activePresentationToken: state.2,
            hasActiveSessionToken: state.3,
            driver: driverSnapshot,
            installationCount: state.4,
            activationCount: state.5,
            deactivationCount: state.6,
            deliveredTickCount: state.7,
            rejectedTickCount: state.8,
            closeCount: state.9
        )
    }

    @discardableResult
    func install(
        handler: @escaping TickHandler
    ) -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        stateLock.lock()
        guard phase == .uninstalled else {
            stateLock.unlock()
            return false
        }
        stateLock.unlock()

        guard driver.install(
            handler: { [weak self] timestamp in
                self?.emit(timestamp: timestamp)
            }
        ) else {
            return false
        }

        stateLock.lock()
        tickHandler = handler
        phase = .idle
        installationCount += 1
        stateLock.unlock()
        return true
    }

    func activate(
        sessionToken: IRAVPlayerSession.Token
    ) -> Token? {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        stateLock.lock()
        guard phase == .idle else {
            stateLock.unlock()
            return nil
        }
        stateLock.unlock()

        guard driver.setActive(true) else {
            return nil
        }

        stateLock.lock()
        generationCounter &+= 1
        let token = Token(
            generation: generationCounter
        )
        activePresentationToken = token
        activeSessionToken = sessionToken
        phase = .active
        activationCount += 1
        stateLock.unlock()
        return token
    }

    @discardableResult
    func deactivate() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        stateLock.lock()
        guard phase == .active else {
            stateLock.unlock()
            return false
        }
        generationCounter &+= 1
        activePresentationToken = nil
        activeSessionToken = nil
        phase = .idle
        deactivationCount += 1
        stateLock.unlock()

        _ = driver.setActive(false)
        return true
    }

    @discardableResult
    func close() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        stateLock.lock()
        guard phase != .closed else {
            stateLock.unlock()
            return false
        }
        generationCounter &+= 1
        phase = .closed
        activePresentationToken = nil
        activeSessionToken = nil
        tickHandler = nil
        closeCount += 1
        stateLock.unlock()

        _ = driver.close()
        return true
    }

    func isCurrent(_ tick: Tick) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return phase == .active
            && activePresentationToken
                == tick.presentationToken
            && activeSessionToken
                == tick.sessionToken
    }

    deinit {
        _ = close()
    }

    private func emit(timestamp: TimeInterval) {
        let delivery: (TickHandler, Tick)?

        stateLock.lock()
        if phase == .active,
           timestamp.isFinite,
           timestamp >= 0,
           let activePresentationToken,
           let activeSessionToken,
           let tickHandler {
            deliveredTickCount += 1
            delivery = (
                tickHandler,
                Tick(
                    presentationToken:
                        activePresentationToken,
                    sessionToken:
                        activeSessionToken,
                    timestamp: timestamp
                )
            )
        } else {
            rejectedTickCount += 1
            delivery = nil
        }
        stateLock.unlock()

        if let delivery {
            delivery.0(delivery.1)
        }
    }
}
