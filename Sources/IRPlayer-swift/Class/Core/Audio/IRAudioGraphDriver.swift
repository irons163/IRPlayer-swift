import AVFoundation
import Foundation

enum IRAudioGraphStage: String, CaseIterable {
    case createGraph
    case addConverterNode
    case addMixerNode
    case addOutputNode
    case openGraph
    case connectConverterToMixer
    case connectMixerToOutput
    case lookupConverterUnit
    case lookupMixerUnit
    case lookupOutputUnit
    case installRenderCallback
    case readOutputFormat
    case validateOutputFormat
    case setOutputFormat
    case setConverterInputFormat
    case setConverterOutputFormat
    case setMixerInputFormat
    case setMixerOutputFormat
    case setMaximumFrames
    case initializeGraph
    case startGraph
    case stopGraph
    case uninitializeGraph
    case closeGraph
    case disposeGraph
    case getVolume
    case setVolume
}

struct IRAudioGraphIssue: Error, Equatable {
    let stage: IRAudioGraphStage
    let status: OSStatus

    var nsError: NSError {
        NSError(
            domain: "IRAudioGraph.\(stage.rawValue)",
            code: Int(status),
            userInfo: nil
        )
    }
}

struct IRAudioGraphBuildFailure: Error, Equatable {
    let issue: IRAudioGraphIssue
    let cleanupIssues: [IRAudioGraphIssue]
}

struct IRAudioGraphResources {
    let graph: AUGraph
    let mixerAudioUnit: AudioUnit
    let format: AudioStreamBasicDescription
}

struct IRAudioGraphBuildOutput {
    let resources: IRAudioGraphResources
    let warnings: [IRAudioGraphIssue]
}

protocol IRAudioGraphDriving: AnyObject {
    func buildGraph(
        renderContext: IRAudioRenderContext,
        preferredSampleRate: Float64
    ) -> Result<IRAudioGraphBuildOutput, IRAudioGraphBuildFailure>

    func start(_ resources: IRAudioGraphResources) -> IRAudioGraphIssue?
    func stop(_ resources: IRAudioGraphResources) -> IRAudioGraphIssue?
    func teardown(_ resources: IRAudioGraphResources) -> [IRAudioGraphIssue]
    func volume(_ resources: IRAudioGraphResources)
        -> Result<Float, IRAudioGraphIssue>
    func setVolume(
        _ volume: Float,
        resources: IRAudioGraphResources
    ) -> IRAudioGraphIssue?
}

protocol IRCoreAudioCalling: AnyObject {
    func newGraph(_ graph: inout AUGraph?) -> OSStatus
    func addNode(
        _ graph: AUGraph,
        description: inout AudioComponentDescription,
        node: inout AUNode
    ) -> OSStatus
    func open(_ graph: AUGraph) -> OSStatus
    func connect(
        _ graph: AUGraph,
        source: AUNode,
        destination: AUNode
    ) -> OSStatus
    func nodeInfo(
        _ graph: AUGraph,
        node: AUNode,
        description: inout AudioComponentDescription,
        audioUnit: inout AudioUnit?
    ) -> OSStatus
    func setRenderCallback(
        _ graph: AUGraph,
        node: AUNode,
        renderContext: IRAudioRenderContext
    ) -> OSStatus
    func getStreamFormat(
        _ audioUnit: AudioUnit,
        format: inout AudioStreamBasicDescription
    ) -> OSStatus
    func setStreamFormat(
        _ audioUnit: AudioUnit,
        scope: AudioUnitScope,
        format: inout AudioStreamBasicDescription
    ) -> OSStatus
    func setMaximumFrames(
        _ audioUnit: AudioUnit,
        maximumFrames: inout UInt32
    ) -> OSStatus
    func initialize(_ graph: AUGraph) -> OSStatus
    func start(_ graph: AUGraph) -> OSStatus
    func stop(_ graph: AUGraph) -> OSStatus
    func uninitialize(_ graph: AUGraph) -> OSStatus
    func close(_ graph: AUGraph) -> OSStatus
    func dispose(_ graph: AUGraph) -> OSStatus
    func volume(_ audioUnit: AudioUnit, value: inout Float) -> OSStatus
    func setVolume(_ audioUnit: AudioUnit, value: Float) -> OSStatus
}

final class IRSystemCoreAudioCalls: IRCoreAudioCalling {
    func newGraph(_ graph: inout AUGraph?) -> OSStatus {
        NewAUGraph(&graph)
    }

    func addNode(
        _ graph: AUGraph,
        description: inout AudioComponentDescription,
        node: inout AUNode
    ) -> OSStatus {
        AUGraphAddNode(graph, &description, &node)
    }

    func open(_ graph: AUGraph) -> OSStatus {
        AUGraphOpen(graph)
    }

    func connect(
        _ graph: AUGraph,
        source: AUNode,
        destination: AUNode
    ) -> OSStatus {
        AUGraphConnectNodeInput(graph, source, 0, destination, 0)
    }

    func nodeInfo(
        _ graph: AUGraph,
        node: AUNode,
        description: inout AudioComponentDescription,
        audioUnit: inout AudioUnit?
    ) -> OSStatus {
        AUGraphNodeInfo(graph, node, &description, &audioUnit)
    }

    func setRenderCallback(
        _ graph: AUGraph,
        node: AUNode,
        renderContext: IRAudioRenderContext
    ) -> OSStatus {
        var callback = AURenderCallbackStruct(
            inputProc: irAudioRenderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(renderContext).toOpaque()
            )
        )
        return AUGraphSetNodeInputCallback(graph, node, 0, &callback)
    }

    func getStreamFormat(
        _ audioUnit: AudioUnit,
        format: inout AudioStreamBasicDescription
    ) -> OSStatus {
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        return AudioUnitGetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &format,
            &size
        )
    }

    func setStreamFormat(
        _ audioUnit: AudioUnit,
        scope: AudioUnitScope,
        format: inout AudioStreamBasicDescription
    ) -> OSStatus {
        AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            scope,
            0,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
    }

    func setMaximumFrames(
        _ audioUnit: AudioUnit,
        maximumFrames: inout UInt32
    ) -> OSStatus {
        AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFrames,
            UInt32(MemoryLayout<UInt32>.size)
        )
    }

    func initialize(_ graph: AUGraph) -> OSStatus {
        AUGraphInitialize(graph)
    }

    func start(_ graph: AUGraph) -> OSStatus {
        AUGraphStart(graph)
    }

    func stop(_ graph: AUGraph) -> OSStatus {
        AUGraphStop(graph)
    }

    func uninitialize(_ graph: AUGraph) -> OSStatus {
        AUGraphUninitialize(graph)
    }

    func close(_ graph: AUGraph) -> OSStatus {
        AUGraphClose(graph)
    }

    func dispose(_ graph: AUGraph) -> OSStatus {
        DisposeAUGraph(graph)
    }

    func volume(_ audioUnit: AudioUnit, value: inout Float) -> OSStatus {
        AudioUnitGetParameter(
            audioUnit,
            kMultiChannelMixerParam_Volume,
            kAudioUnitScope_Input,
            0,
            &value
        )
    }

    func setVolume(_ audioUnit: AudioUnit, value: Float) -> OSStatus {
        AudioUnitSetParameter(
            audioUnit,
            kMultiChannelMixerParam_Volume,
            kAudioUnitScope_Input,
            0,
            value,
            0
        )
    }
}

final class IRCoreAudioGraphDriver: IRAudioGraphDriving {
    private let calls: IRCoreAudioCalling
    private let maximumFrames: UInt32
    private let maximumChannels: UInt32

    init(
        calls: IRCoreAudioCalling = IRSystemCoreAudioCalls(),
        maximumFrames: UInt32 = IRAudioRenderContext.defaultMaximumFrames,
        maximumChannels: UInt32 = IRAudioRenderContext.defaultMaximumChannels
    ) {
        self.calls = calls
        self.maximumFrames = maximumFrames
        self.maximumChannels = maximumChannels
    }

    func buildGraph(
        renderContext: IRAudioRenderContext,
        preferredSampleRate: Float64
    ) -> Result<IRAudioGraphBuildOutput, IRAudioGraphBuildFailure> {
        var graph: AUGraph?
        var graphOpened = false
        var graphInitialized = false
        var warnings: [IRAudioGraphIssue] = []

        func fail(
            _ stage: IRAudioGraphStage,
            _ status: OSStatus
        ) -> Result<IRAudioGraphBuildOutput, IRAudioGraphBuildFailure> {
            let cleanup = cleanupPartialGraph(
                graph,
                opened: graphOpened,
                initialized: graphInitialized
            )
            return .failure(
                IRAudioGraphBuildFailure(
                    issue: IRAudioGraphIssue(stage: stage, status: status),
                    cleanupIssues: cleanup
                )
            )
        }

        var status = calls.newGraph(&graph)
        guard status == noErr, let graph else {
            return fail(.createGraph, status == noErr ? -1 : status)
        }

        var converterDescription = Self.componentDescription(
            type: kAudioUnitType_FormatConverter,
            subtype: kAudioUnitSubType_AUConverter
        )
        var mixerDescription = Self.componentDescription(
            type: kAudioUnitType_Mixer,
            subtype: kAudioUnitSubType_MultiChannelMixer
        )
        var outputDescription = Self.componentDescription(
            type: kAudioUnitType_Output,
            subtype: kAudioUnitSubType_RemoteIO
        )

        var converterNode: AUNode = 0
        status = calls.addNode(
            graph,
            description: &converterDescription,
            node: &converterNode
        )
        guard status == noErr else { return fail(.addConverterNode, status) }

        var mixerNode: AUNode = 0
        status = calls.addNode(
            graph,
            description: &mixerDescription,
            node: &mixerNode
        )
        guard status == noErr else { return fail(.addMixerNode, status) }

        var outputNode: AUNode = 0
        status = calls.addNode(
            graph,
            description: &outputDescription,
            node: &outputNode
        )
        guard status == noErr else { return fail(.addOutputNode, status) }

        status = calls.open(graph)
        guard status == noErr else { return fail(.openGraph, status) }
        graphOpened = true

        status = calls.connect(
            graph,
            source: converterNode,
            destination: mixerNode
        )
        guard status == noErr else {
            return fail(.connectConverterToMixer, status)
        }

        status = calls.connect(
            graph,
            source: mixerNode,
            destination: outputNode
        )
        guard status == noErr else {
            return fail(.connectMixerToOutput, status)
        }

        var converterUnit: AudioUnit?
        status = calls.nodeInfo(
            graph,
            node: converterNode,
            description: &converterDescription,
            audioUnit: &converterUnit
        )
        guard status == noErr, let converterUnit else {
            return fail(.lookupConverterUnit, status == noErr ? -1 : status)
        }

        var mixerUnit: AudioUnit?
        status = calls.nodeInfo(
            graph,
            node: mixerNode,
            description: &mixerDescription,
            audioUnit: &mixerUnit
        )
        guard status == noErr, let mixerUnit else {
            return fail(.lookupMixerUnit, status == noErr ? -1 : status)
        }

        var outputUnit: AudioUnit?
        status = calls.nodeInfo(
            graph,
            node: outputNode,
            description: &outputDescription,
            audioUnit: &outputUnit
        )
        guard status == noErr, let outputUnit else {
            return fail(.lookupOutputUnit, status == noErr ? -1 : status)
        }

        status = calls.setRenderCallback(
            graph,
            node: converterNode,
            renderContext: renderContext
        )
        guard status == noErr else {
            return fail(.installRenderCallback, status)
        }

        var hardwareFormat = AudioStreamBasicDescription()
        status = calls.getStreamFormat(outputUnit, format: &hardwareFormat)
        guard status == noErr else { return fail(.readOutputFormat, status) }

        var commonFormat = hardwareFormat
        if preferredSampleRate.isFinite,
           preferredSampleRate > 0,
           preferredSampleRate != hardwareFormat.mSampleRate {
            var preferredFormat = hardwareFormat
            preferredFormat.mSampleRate = preferredSampleRate
            status = calls.setStreamFormat(
                outputUnit,
                scope: kAudioUnitScope_Input,
                format: &preferredFormat
            )
            if status == noErr {
                commonFormat = preferredFormat
            } else {
                warnings.append(
                    IRAudioGraphIssue(stage: .setOutputFormat, status: status)
                )
            }
        }

        guard IRAudioRenderContext.supportedPCMFormat(
            commonFormat,
            maximumChannels: maximumChannels
        ) else {
            return fail(.validateOutputFormat, -1)
        }

        status = calls.setStreamFormat(
            converterUnit,
            scope: kAudioUnitScope_Input,
            format: &commonFormat
        )
        guard status == noErr else {
            return fail(.setConverterInputFormat, status)
        }

        status = calls.setStreamFormat(
            converterUnit,
            scope: kAudioUnitScope_Output,
            format: &commonFormat
        )
        guard status == noErr else {
            return fail(.setConverterOutputFormat, status)
        }

        status = calls.setStreamFormat(
            mixerUnit,
            scope: kAudioUnitScope_Input,
            format: &commonFormat
        )
        guard status == noErr else {
            return fail(.setMixerInputFormat, status)
        }

        status = calls.setStreamFormat(
            mixerUnit,
            scope: kAudioUnitScope_Output,
            format: &commonFormat
        )
        guard status == noErr else {
            return fail(.setMixerOutputFormat, status)
        }

        var maximumFrames = maximumFrames
        status = calls.setMaximumFrames(
            mixerUnit,
            maximumFrames: &maximumFrames
        )
        if status != noErr {
            warnings.append(
                IRAudioGraphIssue(stage: .setMaximumFrames, status: status)
            )
        }

        status = calls.initialize(graph)
        guard status == noErr else { return fail(.initializeGraph, status) }
        graphInitialized = true

        return .success(
            IRAudioGraphBuildOutput(
                resources: IRAudioGraphResources(
                    graph: graph,
                    mixerAudioUnit: mixerUnit,
                    format: commonFormat
                ),
                warnings: warnings
            )
        )
    }

    func start(_ resources: IRAudioGraphResources) -> IRAudioGraphIssue? {
        issue(
            calls.start(resources.graph),
            stage: .startGraph
        )
    }

    func stop(_ resources: IRAudioGraphResources) -> IRAudioGraphIssue? {
        issue(
            calls.stop(resources.graph),
            stage: .stopGraph
        )
    }

    func teardown(_ resources: IRAudioGraphResources) -> [IRAudioGraphIssue] {
        var issues: [IRAudioGraphIssue] = []
        appendIssue(
            calls.uninitialize(resources.graph),
            stage: .uninitializeGraph,
            to: &issues
        )
        appendIssue(
            calls.close(resources.graph),
            stage: .closeGraph,
            to: &issues
        )
        appendIssue(
            calls.dispose(resources.graph),
            stage: .disposeGraph,
            to: &issues
        )
        return issues
    }

    func volume(
        _ resources: IRAudioGraphResources
    ) -> Result<Float, IRAudioGraphIssue> {
        var value: Float = 1
        let status = calls.volume(resources.mixerAudioUnit, value: &value)
        guard status == noErr else {
            return .failure(
                IRAudioGraphIssue(stage: .getVolume, status: status)
            )
        }
        return .success(value)
    }

    func setVolume(
        _ volume: Float,
        resources: IRAudioGraphResources
    ) -> IRAudioGraphIssue? {
        issue(
            calls.setVolume(resources.mixerAudioUnit, value: volume),
            stage: .setVolume
        )
    }

    private func cleanupPartialGraph(
        _ graph: AUGraph?,
        opened: Bool,
        initialized: Bool
    ) -> [IRAudioGraphIssue] {
        guard let graph else { return [] }
        var issues: [IRAudioGraphIssue] = []
        if initialized {
            appendIssue(
                calls.uninitialize(graph),
                stage: .uninitializeGraph,
                to: &issues
            )
        }
        if opened {
            appendIssue(
                calls.close(graph),
                stage: .closeGraph,
                to: &issues
            )
        }
        appendIssue(
            calls.dispose(graph),
            stage: .disposeGraph,
            to: &issues
        )
        return issues
    }

    private func issue(
        _ status: OSStatus,
        stage: IRAudioGraphStage
    ) -> IRAudioGraphIssue? {
        status == noErr ? nil : IRAudioGraphIssue(
            stage: stage,
            status: status
        )
    }

    private func appendIssue(
        _ status: OSStatus,
        stage: IRAudioGraphStage,
        to issues: inout [IRAudioGraphIssue]
    ) {
        if let issue = issue(status, stage: stage) {
            issues.append(issue)
        }
    }

    private static func componentDescription(
        type: OSType,
        subtype: OSType
    ) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: type,
            componentSubType: subtype,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}
