import AVFoundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRAudioGraphDriverTests: XCTestCase {
    func testSuccessfulBuildConfiguresCompleteGraphAndTeardownOrder()
        throws
    {
        let calls = RecordingCoreAudioCalls()
        let driver = IRCoreAudioGraphDriver(calls: calls)
        let context = IRAudioRenderContext()

        let output = try driver.buildGraph(
            renderContext: context,
            preferredSampleRate: 44_100
        ).get()

        XCTAssertEqual(output.resources.format.mSampleRate, 44_100)
        XCTAssertEqual(output.resources.format.mChannelsPerFrame, 2)
        XCTAssertEqual(output.warnings, [])
        XCTAssertEqual(calls.addedComponentSubtypes, [
            kAudioUnitSubType_AUConverter,
            kAudioUnitSubType_MultiChannelMixer,
            kAudioUnitSubType_RemoteIO
        ])
        XCTAssertEqual(calls.connections, [
            RecordingCoreAudioCalls.Connection(source: 1, destination: 2),
            RecordingCoreAudioCalls.Connection(source: 2, destination: 3)
        ])
        XCTAssertEqual(calls.maximumFrames, 4_096)
        XCTAssertEqual(calls.disposeCount, 0)

        XCTAssertEqual(driver.teardown(output.resources), [])
        XCTAssertEqual(
            Array(calls.operations.suffix(3)),
            ["uninitialize", "close", "dispose"]
        )
        XCTAssertEqual(calls.disposeCount, 1)
    }

    func testEveryMandatoryBuildFailureDisposesPartialGraphExactlyOnce() {
        let stages: [IRAudioGraphStage] = [
            .createGraph,
            .addConverterNode,
            .addMixerNode,
            .addOutputNode,
            .openGraph,
            .connectConverterToMixer,
            .connectMixerToOutput,
            .lookupConverterUnit,
            .lookupMixerUnit,
            .lookupOutputUnit,
            .installRenderCallback,
            .readOutputFormat,
            .setConverterInputFormat,
            .setConverterOutputFormat,
            .setMixerInputFormat,
            .setMixerOutputFormat,
            .initializeGraph
        ]

        for stage in stages {
            let calls = RecordingCoreAudioCalls()
            calls.failureStage = stage
            let driver = IRCoreAudioGraphDriver(calls: calls)

            switch driver.buildGraph(
                renderContext: IRAudioRenderContext(),
                preferredSampleRate: 48_000
            ) {
            case .success:
                XCTFail("Expected failure at \(stage)")

            case .failure(let failure):
                XCTAssertEqual(failure.issue.stage, stage)
            }

            XCTAssertEqual(
                calls.disposeCount,
                1,
                "Graph leaked or double-disposed at \(stage)"
            )
            if stage == .createGraph ||
                stage == .addConverterNode ||
                stage == .addMixerNode ||
                stage == .addOutputNode ||
                stage == .openGraph {
                XCTAssertEqual(calls.closeCount, 0, "\(stage)")
            } else {
                XCTAssertEqual(calls.closeCount, 1, "\(stage)")
            }
            XCTAssertEqual(calls.uninitializeCount, 0, "\(stage)")
        }
    }

    func testMissingGraphAfterSuccessfulCreateStatusFailsWithoutDispose() {
        let calls = RecordingCoreAudioCalls()
        calls.returnNilGraph = true
        let driver = IRCoreAudioGraphDriver(calls: calls)

        switch driver.buildGraph(
            renderContext: IRAudioRenderContext(),
            preferredSampleRate: 48_000
        ) {
        case .success:
            XCTFail("Missing graph must fail")
        case .failure(let failure):
            XCTAssertEqual(failure.issue.stage, .createGraph)
            XCTAssertEqual(failure.issue.status, -1)
        }
        XCTAssertEqual(calls.disposeCount, 0)
    }

    func testPreferredRateFailureIsWarningAndKeepsHardwareFormat()
        throws
    {
        let calls = RecordingCoreAudioCalls()
        calls.failureStage = .setOutputFormat
        let driver = IRCoreAudioGraphDriver(calls: calls)

        let output = try driver.buildGraph(
            renderContext: IRAudioRenderContext(),
            preferredSampleRate: 44_100
        ).get()

        XCTAssertEqual(output.resources.format.mSampleRate, 48_000)
        XCTAssertEqual(
            output.warnings,
            [
                IRAudioGraphIssue(
                    stage: .setOutputFormat,
                    status: RecordingCoreAudioCalls.failureStatus
                )
            ]
        )
        _ = driver.teardown(output.resources)
    }

    func testMaximumFramesFailureIsWarningAndBuildStillPublishes()
        throws
    {
        let calls = RecordingCoreAudioCalls()
        calls.failureStage = .setMaximumFrames
        let driver = IRCoreAudioGraphDriver(calls: calls)

        let output = try driver.buildGraph(
            renderContext: IRAudioRenderContext(),
            preferredSampleRate: 48_000
        ).get()

        XCTAssertEqual(
            output.warnings.first?.stage,
            .setMaximumFrames
        )
        _ = driver.teardown(output.resources)
    }

    func testUnsupportedHardwareFormatFailsAndCleansOpenedGraph() {
        let calls = RecordingCoreAudioCalls()
        calls.outputFormat = makeTestPCMFormat(
            channels:
                IRAudioRenderContext.defaultMaximumChannels + 1
        )
        let driver = IRCoreAudioGraphDriver(calls: calls)

        switch driver.buildGraph(
            renderContext: IRAudioRenderContext(),
            preferredSampleRate: 48_000
        ) {
        case .success:
            XCTFail("Unsupported channel count must fail")
        case .failure(let failure):
            XCTAssertEqual(failure.issue.stage, .validateOutputFormat)
        }

        XCTAssertEqual(calls.closeCount, 1)
        XCTAssertEqual(calls.disposeCount, 1)
    }

    func testUnpackedOrInconsistentPCMLayoutFailsAndCleansOpenedGraph() {
        var unpacked = makeTestPCMFormat()
        unpacked.mFormatFlags &= ~kAudioFormatFlagIsPacked
        var inconsistent = makeTestPCMFormat()
        inconsistent.mBytesPerFrame = 4

        for format in [unpacked, inconsistent] {
            let calls = RecordingCoreAudioCalls()
            calls.outputFormat = format
            let driver = IRCoreAudioGraphDriver(calls: calls)

            switch driver.buildGraph(
                renderContext: IRAudioRenderContext(),
                preferredSampleRate: 48_000
            ) {
            case .success:
                XCTFail("Unsupported PCM layout must fail")
            case .failure(let failure):
                XCTAssertEqual(
                    failure.issue.stage,
                    .validateOutputFormat
                )
            }

            XCTAssertEqual(calls.closeCount, 1)
            XCTAssertEqual(calls.disposeCount, 1)
        }
    }

    func testStartStopAndVolumeMapFailuresToExactStages() throws {
        let calls = RecordingCoreAudioCalls()
        let driver = IRCoreAudioGraphDriver(calls: calls)
        let resources = try driver.buildGraph(
            renderContext: IRAudioRenderContext(),
            preferredSampleRate: 48_000
        ).get().resources

        calls.failureStage = .startGraph
        XCTAssertEqual(driver.start(resources)?.stage, .startGraph)
        calls.failureStage = .stopGraph
        XCTAssertEqual(driver.stop(resources)?.stage, .stopGraph)
        calls.failureStage = .getVolume
        switch driver.volume(resources) {
        case .success:
            XCTFail("Volume read should fail")
        case .failure(let issue):
            XCTAssertEqual(issue.stage, .getVolume)
        }
        calls.failureStage = .setVolume
        XCTAssertEqual(
            driver.setVolume(0.25, resources: resources)?.stage,
            .setVolume
        )

        calls.failureStage = nil
        XCTAssertNil(driver.start(resources))
        XCTAssertNil(driver.stop(resources))
        XCTAssertNoThrow(try driver.volume(resources).get())
        XCTAssertNil(driver.setVolume(0.75, resources: resources))
        XCTAssertEqual(calls.setVolumeValues.last, 0.75)
        _ = driver.teardown(resources)
    }
}

private final class RecordingCoreAudioCalls: IRCoreAudioCalling {
    struct Connection: Equatable {
        let source: AUNode
        let destination: AUNode
    }

    static let failureStatus: OSStatus = -9_999

    let graph = OpaquePointer(bitPattern: 0x301)!
    let converterUnit = OpaquePointer(bitPattern: 0x401)!
    let mixerUnit = OpaquePointer(bitPattern: 0x402)!
    let outputUnit = OpaquePointer(bitPattern: 0x403)!

    var failureStage: IRAudioGraphStage?
    var returnNilGraph = false
    var outputFormat = makeTestPCMFormat()
    var operations: [String] = []
    var addedComponentSubtypes: [OSType] = []
    var connections: [Connection] = []
    var maximumFrames: UInt32?
    var disposeCount = 0
    var closeCount = 0
    var uninitializeCount = 0
    var setVolumeValues: [Float] = []
    var storedVolume: Float = 0.5

    func newGraph(_ graph: inout AUGraph?) -> OSStatus {
        operations.append("create")
        graph = returnNilGraph ? nil : self.graph
        return status(for: .createGraph)
    }

    func addNode(
        _ graph: AUGraph,
        description: inout AudioComponentDescription,
        node: inout AUNode
    ) -> OSStatus {
        addedComponentSubtypes.append(description.componentSubType)
        let stage: IRAudioGraphStage
        switch addedComponentSubtypes.count {
        case 1:
            stage = .addConverterNode
            node = 1
        case 2:
            stage = .addMixerNode
            node = 2
        default:
            stage = .addOutputNode
            node = 3
        }
        operations.append(stage.rawValue)
        return status(for: stage)
    }

    func open(_ graph: AUGraph) -> OSStatus {
        operations.append("open")
        return status(for: .openGraph)
    }

    func connect(
        _ graph: AUGraph,
        source: AUNode,
        destination: AUNode
    ) -> OSStatus {
        connections.append(Connection(source: source, destination: destination))
        let stage: IRAudioGraphStage =
            connections.count == 1
            ? .connectConverterToMixer
            : .connectMixerToOutput
        operations.append(stage.rawValue)
        return status(for: stage)
    }

    func nodeInfo(
        _ graph: AUGraph,
        node: AUNode,
        description: inout AudioComponentDescription,
        audioUnit: inout AudioUnit?
    ) -> OSStatus {
        let stage: IRAudioGraphStage
        switch node {
        case 1:
            stage = .lookupConverterUnit
            audioUnit = converterUnit
        case 2:
            stage = .lookupMixerUnit
            audioUnit = mixerUnit
        default:
            stage = .lookupOutputUnit
            audioUnit = outputUnit
        }
        operations.append(stage.rawValue)
        return status(for: stage)
    }

    func setRenderCallback(
        _ graph: AUGraph,
        node: AUNode,
        renderContext: IRAudioRenderContext
    ) -> OSStatus {
        operations.append("callback")
        return status(for: .installRenderCallback)
    }

    func getStreamFormat(
        _ audioUnit: AudioUnit,
        format: inout AudioStreamBasicDescription
    ) -> OSStatus {
        operations.append("getFormat")
        format = outputFormat
        return status(for: .readOutputFormat)
    }

    func setStreamFormat(
        _ audioUnit: AudioUnit,
        scope: AudioUnitScope,
        format: inout AudioStreamBasicDescription
    ) -> OSStatus {
        let stage: IRAudioGraphStage
        if audioUnit == outputUnit {
            stage = .setOutputFormat
        } else if audioUnit == converterUnit {
            stage = scope == kAudioUnitScope_Input
                ? .setConverterInputFormat
                : .setConverterOutputFormat
        } else {
            stage = scope == kAudioUnitScope_Input
                ? .setMixerInputFormat
                : .setMixerOutputFormat
        }
        operations.append(stage.rawValue)
        return status(for: stage)
    }

    func setMaximumFrames(
        _ audioUnit: AudioUnit,
        maximumFrames: inout UInt32
    ) -> OSStatus {
        self.maximumFrames = maximumFrames
        operations.append("maximumFrames")
        return status(for: .setMaximumFrames)
    }

    func initialize(_ graph: AUGraph) -> OSStatus {
        operations.append("initialize")
        return status(for: .initializeGraph)
    }

    func start(_ graph: AUGraph) -> OSStatus {
        operations.append("start")
        return status(for: .startGraph)
    }

    func stop(_ graph: AUGraph) -> OSStatus {
        operations.append("stop")
        return status(for: .stopGraph)
    }

    func uninitialize(_ graph: AUGraph) -> OSStatus {
        operations.append("uninitialize")
        uninitializeCount += 1
        return status(for: .uninitializeGraph)
    }

    func close(_ graph: AUGraph) -> OSStatus {
        operations.append("close")
        closeCount += 1
        return status(for: .closeGraph)
    }

    func dispose(_ graph: AUGraph) -> OSStatus {
        operations.append("dispose")
        disposeCount += 1
        return status(for: .disposeGraph)
    }

    func volume(_ audioUnit: AudioUnit, value: inout Float) -> OSStatus {
        value = storedVolume
        return status(for: .getVolume)
    }

    func setVolume(_ audioUnit: AudioUnit, value: Float) -> OSStatus {
        setVolumeValues.append(value)
        storedVolume = value
        return status(for: .setVolume)
    }

    private func status(for stage: IRAudioGraphStage) -> OSStatus {
        failureStage == stage ? Self.failureStatus : noErr
    }
}
