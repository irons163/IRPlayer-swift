import AVFoundation
import Foundation
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

func makeTestPCMFormat(
    sampleRate: Float64 = 48_000,
    channels: UInt32 = 2,
    bitsPerChannel: UInt32 = 32,
    flags: AudioFormatFlags = kAudioFormatFlagIsFloat |
        kAudioFormatFlagIsPacked
) -> AudioStreamBasicDescription {
    let bytesPerSample = bitsPerChannel / 8
    let bytesPerFrame =
        flags & kAudioFormatFlagIsNonInterleaved != 0
        ? bytesPerSample
        : bytesPerSample * channels
    return AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: flags,
        mBytesPerPacket: bytesPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: channels,
        mBitsPerChannel: bitsPerChannel,
        mReserved: 0
    )
}

func makeTestAudioGraphResources(
    format: AudioStreamBasicDescription = makeTestPCMFormat()
) -> IRAudioGraphResources {
    IRAudioGraphResources(
        graph: OpaquePointer(bitPattern: 0x101)!,
        mixerAudioUnit: OpaquePointer(bitPattern: 0x202)!,
        format: format
    )
}

final class TestAudioGraphDriver:
    IRAudioGraphDriving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var queuedBuildResults:
        [Result<IRAudioGraphBuildOutput, IRAudioGraphBuildFailure>]
    private var storedEvents: [String] = []
    private var storedBuildCount = 0
    private var storedStartCount = 0
    private var storedStopCount = 0
    private var storedTeardownCount = 0
    private var storedGetVolumeCount = 0
    private var storedSetVolumes: [Float] = []
    private var storedVolume: Float = 1

    var onBuild: (() -> Void)?
    var startIssue: IRAudioGraphIssue?
    var stopIssue: IRAudioGraphIssue?
    var teardownIssues: [IRAudioGraphIssue] = []
    var volumeIssue: IRAudioGraphIssue?
    var setVolumeIssue: IRAudioGraphIssue?

    init(
        format: AudioStreamBasicDescription = makeTestPCMFormat()
    ) {
        queuedBuildResults = [
            .success(
                IRAudioGraphBuildOutput(
                    resources: makeTestAudioGraphResources(format: format),
                    warnings: []
                )
            )
        ]
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    var buildCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedBuildCount
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStartCount
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStopCount
    }

    var teardownCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedTeardownCount
    }

    var getVolumeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedGetVolumeCount
    }

    var setVolumes: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return storedSetVolumes
    }

    func enqueueBuild(
        _ result:
            Result<IRAudioGraphBuildOutput, IRAudioGraphBuildFailure>
    ) {
        lock.lock()
        queuedBuildResults.append(result)
        lock.unlock()
    }

    func replaceBuildResults(
        _ results:
            [Result<IRAudioGraphBuildOutput, IRAudioGraphBuildFailure>]
    ) {
        lock.lock()
        queuedBuildResults = results
        lock.unlock()
    }

    func setStoredVolume(_ value: Float) {
        lock.lock()
        storedVolume = value
        lock.unlock()
    }

    func buildGraph(
        renderContext: IRAudioRenderContext,
        preferredSampleRate: Float64
    ) -> Result<IRAudioGraphBuildOutput, IRAudioGraphBuildFailure> {
        lock.lock()
        storedBuildCount += 1
        storedEvents.append("build")
        let result = queuedBuildResults.count > 1
            ? queuedBuildResults.removeFirst()
            : queuedBuildResults[0]
        let onBuild = onBuild
        lock.unlock()
        onBuild?()
        return result
    }

    func start(
        _ resources: IRAudioGraphResources
    ) -> IRAudioGraphIssue? {
        lock.lock()
        storedStartCount += 1
        storedEvents.append("start")
        let issue = startIssue
        lock.unlock()
        return issue
    }

    func stop(
        _ resources: IRAudioGraphResources
    ) -> IRAudioGraphIssue? {
        lock.lock()
        storedStopCount += 1
        storedEvents.append("stop")
        let issue = stopIssue
        lock.unlock()
        return issue
    }

    func teardown(
        _ resources: IRAudioGraphResources
    ) -> [IRAudioGraphIssue] {
        lock.lock()
        storedTeardownCount += 1
        storedEvents.append("teardown")
        let issues = teardownIssues
        lock.unlock()
        return issues
    }

    func volume(
        _ resources: IRAudioGraphResources
    ) -> Result<Float, IRAudioGraphIssue> {
        lock.lock()
        storedGetVolumeCount += 1
        storedEvents.append("getVolume")
        let issue = volumeIssue
        let volume = storedVolume
        lock.unlock()
        if let issue {
            return .failure(issue)
        }
        return .success(volume)
    }

    func setVolume(
        _ volume: Float,
        resources: IRAudioGraphResources
    ) -> IRAudioGraphIssue? {
        lock.lock()
        storedSetVolumes.append(volume)
        storedVolume = volume
        storedEvents.append("setVolume")
        let issue = setVolumeIssue
        lock.unlock()
        return issue
    }
}

final class TestAudioManagerDelegate:
    IRAudioManagerDelegate,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedRenderCount = 0
    var render: (
        (
            UnsafeMutablePointer<Float>,
            UInt32,
            UInt32
        ) -> Void
    )?

    var renderCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRenderCount
    }

    func audioManager(
        _ audioManager: IRAudioManager,
        outputData: UnsafeMutablePointer<Float>,
        numberOfFrames: UInt32,
        numberOfChannels: UInt32
    ) {
        lock.lock()
        storedRenderCount += 1
        let render = render
        lock.unlock()
        render?(outputData, numberOfFrames, numberOfChannels)
    }
}

func makeTestAudioManager(
    driver: TestAudioGraphDriver = TestAudioGraphDriver(),
    notificationCenter: NotificationCenter = NotificationCenter(),
    sampleRate: Float64 = 48_000,
    channels: UInt32 = 2
) -> IRAudioManager {
    IRAudioManager(
        graphSession: IRAudioGraphSession(driver: driver),
        hardwareInfo: IRAudioHardwareInfo(
            sampleRate: { sampleRate },
            channelCount: { channels }
        ),
        notificationCenter: notificationCenter
    )
}
