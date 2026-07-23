import AVFoundation
import Foundation

final class IRAudioGraphSession: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        case building
        case ready
        case running
        case resetting
        case closed
    }

    struct Diagnostics {
        let phase: Phase
        let hasGraph: Bool
        let hasMixerAudioUnit: Bool
        let renderContext: IRAudioRenderContext.Diagnostics
        let prepareCount: Int
        let startCount: Int
        let pauseCount: Int
        let resetCount: Int
        let teardownCount: Int
        let lastBuildFailure: IRAudioGraphBuildFailure?
        let lastOperationalIssue: IRAudioGraphIssue?
        let warnings: [IRAudioGraphIssue]
    }

    private let stateLock = NSLock()
    private let mutationLock = NSLock()
    private let driver: IRAudioGraphDriving
    let renderContext: IRAudioRenderContext

    private var phase: Phase = .idle
    private var resources: IRAudioGraphResources?
    private var prepareCount = 0
    private var startCount = 0
    private var pauseCount = 0
    private var resetCount = 0
    private var teardownCount = 0
    private var lastBuildFailure: IRAudioGraphBuildFailure?
    private var lastOperationalIssue: IRAudioGraphIssue?
    private var warnings: [IRAudioGraphIssue] = []

    init(
        driver: IRAudioGraphDriving = IRCoreAudioGraphDriver(),
        renderContext: IRAudioRenderContext = IRAudioRenderContext()
    ) {
        self.driver = driver
        self.renderContext = renderContext
    }

    deinit {
        close()
    }

    var diagnostics: Diagnostics {
        stateLock.lock()
        let phase = self.phase
        let hasGraph = resources != nil
        let prepareCount = self.prepareCount
        let startCount = self.startCount
        let pauseCount = self.pauseCount
        let resetCount = self.resetCount
        let teardownCount = self.teardownCount
        let lastBuildFailure = self.lastBuildFailure
        let lastOperationalIssue = self.lastOperationalIssue
        let warnings = self.warnings
        stateLock.unlock()

        let snapshot = Diagnostics(
            phase: phase,
            hasGraph: hasGraph,
            hasMixerAudioUnit: hasGraph,
            renderContext: renderContext.diagnostics,
            prepareCount: prepareCount,
            startCount: startCount,
            pauseCount: pauseCount,
            resetCount: resetCount,
            teardownCount: teardownCount,
            lastBuildFailure: lastBuildFailure,
            lastOperationalIssue: lastOperationalIssue,
            warnings: warnings
        )
        return snapshot
    }

    var isPrepared: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return phase == .ready || phase == .running
    }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return phase == .running
    }

    var samplingRate: Float64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return resources?.format.mSampleRate ?? 0
    }

    var numberOfChannels: UInt32 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return resources?.format.mChannelsPerFrame ?? 0
    }

    @discardableResult
    func prepare(preferredSampleRate: Float64) -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        return prepareLocked(preferredSampleRate: preferredSampleRate)
    }

    @discardableResult
    func start(
        owner: IRAudioManager,
        delegate: IRAudioManagerDelegate,
        preferredSampleRate: Float64
    ) -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        if phaseSnapshot == .running {
            renderContext.activate(owner: owner, delegate: delegate)
            return true
        }
        guard prepareLocked(preferredSampleRate: preferredSampleRate),
              let resources = resourceSnapshot,
              phaseSnapshot == .ready else {
            return false
        }

        renderContext.activate(owner: owner, delegate: delegate)
        if let issue = driver.start(resources) {
            renderContext.deactivate()
            recordOperationalIssue(issue)
            return false
        }

        stateLock.lock()
        guard phase == .ready, self.resources != nil else {
            stateLock.unlock()
            renderContext.deactivate()
            _ = driver.stop(resources)
            return false
        }
        phase = .running
        startCount += 1
        lastOperationalIssue = nil
        stateLock.unlock()
        return true
    }

    @discardableResult
    func pause() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        return pauseLocked()
    }

    @discardableResult
    func reset() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard phaseSnapshot != .closed else { return false }
        return drainLocked(finalPhase: .idle, countReset: true)
    }

    @discardableResult
    func close() -> Bool {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard phaseSnapshot != .closed else { return false }
        _ = drainLocked(finalPhase: .closed, countReset: false)
        return true
    }

    func volume(default defaultValue: Float = 1) -> Float {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        guard let resources = resourceSnapshot,
              phaseSnapshot == .ready || phaseSnapshot == .running else {
            return defaultValue
        }
        switch driver.volume(resources) {
        case .success(let value):
            clearOperationalIssue()
            return value
        case .failure(let issue):
            recordOperationalIssue(issue)
            return defaultValue
        }
    }

    func setVolume(_ volume: Float) {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        guard let resources = resourceSnapshot,
              phaseSnapshot == .ready || phaseSnapshot == .running else {
            return
        }
        if let issue = driver.setVolume(volume, resources: resources) {
            recordOperationalIssue(issue)
        } else {
            clearOperationalIssue()
        }
    }

    func renderFrames(
        _ numberOfFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        renderContext.renderFrames(numberOfFrames, ioData: ioData)
    }

    private func prepareLocked(preferredSampleRate: Float64) -> Bool {
        switch phaseSnapshot {
        case .ready, .running:
            return true
        case .closed, .building, .resetting:
            return false
        case .idle:
            break
        }

        stateLock.lock()
        phase = .building
        stateLock.unlock()

        switch driver.buildGraph(
            renderContext: renderContext,
            preferredSampleRate: preferredSampleRate
        ) {
        case .success(let output):
            renderContext.configure(format: output.resources.format)
            stateLock.lock()
            resources = output.resources
            warnings.append(contentsOf: output.warnings)
            phase = .ready
            prepareCount += 1
            lastBuildFailure = nil
            lastOperationalIssue = nil
            stateLock.unlock()
            return true

        case .failure(let failure):
            stateLock.lock()
            resources = nil
            warnings.append(contentsOf: failure.cleanupIssues)
            phase = .idle
            lastBuildFailure = failure
            stateLock.unlock()
            return false
        }
    }

    private func pauseLocked() -> Bool {
        guard phaseSnapshot == .running,
              let resources = resourceSnapshot else {
            renderContext.deactivate()
            return false
        }

        renderContext.deactivate()
        let issue = driver.stop(resources)
        stateLock.lock()
        if phase == .running {
            phase = .ready
        }
        pauseCount += 1
        lastOperationalIssue = issue
        if let issue {
            warnings.append(issue)
        }
        stateLock.unlock()
        return issue == nil
    }

    private func drainLocked(
        finalPhase: Phase,
        countReset: Bool
    ) -> Bool {
        let previousPhase = phaseSnapshot
        let resources = resourceSnapshot
        guard previousPhase != .closed else { return false }

        stateLock.lock()
        phase = .resetting
        stateLock.unlock()

        if previousPhase == .running {
            renderContext.deactivate()
            if let resources, let issue = driver.stop(resources) {
                appendWarning(issue)
                recordOperationalIssue(issue)
            }
            stateLock.lock()
            pauseCount += 1
            stateLock.unlock()
        } else {
            renderContext.deactivate()
        }

        var teardownIssues: [IRAudioGraphIssue] = []
        if let resources {
            teardownIssues = driver.teardown(resources)
        }

        stateLock.lock()
        self.resources = nil
        warnings.append(contentsOf: teardownIssues)
        if countReset, resources != nil {
            resetCount += 1
        }
        if resources != nil {
            teardownCount += 1
        }
        phase = finalPhase
        stateLock.unlock()
        return resources != nil
    }

    private var phaseSnapshot: Phase {
        stateLock.lock()
        defer { stateLock.unlock() }
        return phase
    }

    private var resourceSnapshot: IRAudioGraphResources? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return resources
    }

    private func appendWarning(_ issue: IRAudioGraphIssue) {
        stateLock.lock()
        warnings.append(issue)
        stateLock.unlock()
    }

    private func recordOperationalIssue(_ issue: IRAudioGraphIssue) {
        stateLock.lock()
        lastOperationalIssue = issue
        stateLock.unlock()
    }

    private func clearOperationalIssue() {
        stateLock.lock()
        lastOperationalIssue = nil
        stateLock.unlock()
    }
}
