//
//  IRAudioManager.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation
import AVFoundation
import Accelerate

enum IRAudioManagerInterruptionType: UInt {
    case begin
    case ended
}

enum IRAudioManagerInterruptionOption: UInt {
    case none
    case shouldResume
}

enum IRAudioManagerRouteChangeReason: UInt {
    case oldDeviceUnavailable
}

protocol IRAudioManagerDelegate: AnyObject {
    func audioManager(_ audioManager: IRAudioManager, outputData: UnsafeMutablePointer<Float>, numberOfFrames: UInt32, numberOfChannels: UInt32)
}

class IRAudioManager: NSObject {

//    static let shared = IRAudioManager()

    private var _outData: UnsafeMutablePointer<Float>?
    private var outputContext: IRAudioOutputContext?

    private weak var handlerTarget: AnyObject?
    private var interruptionHandler: IRAudioManagerInterruptionHandler?
    private var routeChangeHandler: IRAudioManagerRouteChangeHandler?

    private var registered = false

    #if os(macOS)
    private var audioSession = IRMacAudioSession.shared
    #else
    private var audioSession = AVAudioSession.sharedInstance()
    #endif

    private var error: NSError?
    private var warning: NSError?

    private var _playing = false
    weak var delegate: IRAudioManagerDelegate?

    var volume: Float {
        get {
            guard registered,
                  let audioUnit = outputContext?.mixerNodeContext.audioUnit else { return 1.0 }
            var volume: AudioUnitParameterValue = 1.0
            let param: AudioUnitParameterID = kMultiChannelMixerParam_Volume
            let result = AudioUnitGetParameter(audioUnit,
                                               param,
                                               kAudioUnitScope_Input,
                                               0,
                                               &volume)
            warning = checkError(result, domain: "graph get mixer volume error")
            if let warning = warning {
                delegateWarningCallback()
            }
            return volume
        }
        set {
            guard registered,
                  let audioUnit = outputContext?.mixerNodeContext.audioUnit else { return }
            let param: AudioUnitParameterID = kMultiChannelMixerParam_Volume
            let result = AudioUnitSetParameter(audioUnit,
                                               param,
                                               kAudioUnitScope_Input,
                                               0,
                                               newValue,
                                               0)
            warning = checkError(result, domain: "graph set mixer volume error")
            if let warning = warning {
                delegateWarningCallback()
            }
        }
    }

    var playing: Bool {
        return _playing
    }

    var samplingRate: Float64 {
        let number = outputContext?.commonFormat.mSampleRate ?? 0
        return number > 0 ? number : Float64(audioSession.sampleRate)
    }

    var numberOfChannels: UInt32 {
        let number = outputContext?.commonFormat.mChannelsPerFrame ?? 0
        return number > 0 ? number : UInt32(audioSession.outputNumberOfChannels)
    }

    override init() {
        super.init()
        _outData = UnsafeMutablePointer<Float>.allocate(capacity: IRAudioManager.maxFrameSize * IRAudioManager.maxChan)

        #if !os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterruptionHandler(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionRouteChangeHandler(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        #endif
    }

    deinit {
        unregisterAudioSession()
        _outData?.deallocate()
        NotificationCenter.default.removeObserver(self)
    }

    func setHandlerTarget(_ handlerTarget: AnyObject, interruption: @escaping IRAudioManagerInterruptionHandler, routeChange: @escaping IRAudioManagerRouteChangeHandler) {
        self.handlerTarget = handlerTarget
        self.interruptionHandler = interruption
        self.routeChangeHandler = routeChange
    }

    func removeHandlerTarget(_ handlerTarget: AnyObject) {
        if self.handlerTarget === handlerTarget || self.handlerTarget == nil {
            self.handlerTarget = nil
            self.interruptionHandler = nil
            self.routeChangeHandler = nil
        }
    }

    @objc private func audioSessionInterruptionHandler(_ notification: Notification) {
        guard let handlerTarget = handlerTarget, let interruptionHandler = interruptionHandler else { return }
        let avType = AVAudioSession.InterruptionType(rawValue: notification.userInfo?[AVAudioSessionInterruptionTypeKey] as! UInt)!
        let type: IRAudioManagerInterruptionType = (avType == .ended) ? .ended : .begin
        var option: IRAudioManagerInterruptionOption = .none
        if let avOption = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
            if avOption == AVAudioSession.InterruptionOptions.shouldResume.rawValue {
                option = .shouldResume
            }
        }
        interruptionHandler(handlerTarget, self, type, option)
    }

    @objc private func audioSessionRouteChangeHandler(_ notification: Notification) {
        guard let handlerTarget = handlerTarget, let routeChangeHandler = routeChangeHandler else { return }
        let avReason = AVAudioSession.RouteChangeReason(rawValue: notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as! UInt)!
        if avReason == .oldDeviceUnavailable {
            routeChangeHandler(handlerTarget, self, .oldDeviceUnavailable)
        }
    }

    func registerAudioSession() -> Bool {
        if !registered {
            if setupAudioUnit() {
                registered = true
            }
        }
        return registered
    }

    func unregisterAudioSession() {
        if registered, let graph = outputContext?.graph {
            var result = AUGraphUninitialize(graph)
            warning = checkError(result, domain: "graph uninitialize error")
            if let warning = warning {
                delegateWarningCallback()
            }
            result = AUGraphClose(graph)
            warning = checkError(result, domain: "graph close error")
            if let warning = warning {
                delegateWarningCallback()
            }
            result = DisposeAUGraph(graph)
            warning = checkError(result, domain: "graph dispose error")
            if let warning = warning {
                delegateWarningCallback()
            }
            outputContext = nil
            registered = false
        }
    }

    private func setupAudioUnit() -> Bool {
        var result: OSStatus
        var outputContext = IRAudioOutputContext()
        defer {
            self.outputContext = outputContext
        }

        result = NewAUGraph(&outputContext.graph)
        error = checkError(result, domain: "create graph error")
        guard error == nil else {
            delegateErrorCallback()
            return false
        }

        var converterDescription = AudioComponentDescription(componentType: kAudioUnitType_FormatConverter,
                                                             componentSubType: kAudioUnitSubType_AUConverter,
                                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                                             componentFlags: 0,
                                                             componentFlagsMask: 0)
        result = AUGraphAddNode(outputContext.graph!, &converterDescription, &outputContext.converterNodeContext.node)
        error = checkError(result, domain: "graph add converter node error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        var mixerDescription = AudioComponentDescription(componentType: kAudioUnitType_Mixer,
                                                         componentSubType: kAudioUnitSubType_MultiChannelMixer,
                                                         componentManufacturer: kAudioUnitManufacturer_Apple,
                                                         componentFlags: 0,
                                                         componentFlagsMask: 0)
        result = AUGraphAddNode(outputContext.graph!, &mixerDescription, &outputContext.mixerNodeContext.node)
        error = checkError(result, domain: "graph add mixer node error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        var outputDescription = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                          componentSubType: kAudioUnitSubType_RemoteIO,
                                                          componentManufacturer: kAudioUnitManufacturer_Apple,
                                                          componentFlags: 0,
                                                          componentFlagsMask: 0)
        result = AUGraphAddNode(outputContext.graph!, &outputDescription, &outputContext.outputNodeContext.node)
        error = checkError(result, domain: "graph add output node error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AUGraphOpen(outputContext.graph!)
        error = checkError(result, domain: "open graph error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AUGraphConnectNodeInput(outputContext.graph!,
                                         outputContext.converterNodeContext.node,
                                         0,
                                         outputContext.mixerNodeContext.node,
                                         0)
        error = checkError(result, domain: "graph connect converter and mixer error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AUGraphConnectNodeInput(outputContext.graph!,
                                         outputContext.mixerNodeContext.node,
                                         0,
                                         outputContext.outputNodeContext.node,
                                         0)
        error = checkError(result, domain: "graph connect mixer and output error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AUGraphNodeInfo(outputContext.graph!,
                                 outputContext.converterNodeContext.node,
                                 &converterDescription,
                                 &outputContext.converterNodeContext.audioUnit)
        error = checkError(result, domain: "graph get converter audio unit error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AUGraphNodeInfo(outputContext.graph!,
                                 outputContext.mixerNodeContext.node,
                                 &mixerDescription,
                                 &outputContext.mixerNodeContext.audioUnit)
        error = checkError(result, domain: "graph get mixer audio unit error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AUGraphNodeInfo(outputContext.graph!,
                                 outputContext.outputNodeContext.node,
                                 &outputDescription,
                                 &outputContext.outputNodeContext.audioUnit)
        error = checkError(result, domain: "graph get output audio unit error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        var converterCallback = AURenderCallbackStruct(inputProc: renderCallback,
                                                       inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        result = AUGraphSetNodeInputCallback(outputContext.graph!,
                                             outputContext.converterNodeContext.node,
                                             0,
                                             &converterCallback)
        error = checkError(result, domain: "graph add converter input callback error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        var audioStreamBasicDescriptionSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        result = AudioUnitGetProperty(outputContext.outputNodeContext.audioUnit!,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, 0,
                                      &outputContext.commonFormat,
                                      &audioStreamBasicDescriptionSize)
        warning = checkError(result, domain: "get hardware output stream format error")
        if let warning = warning {
            delegateWarningCallback()
        } else {
            if audioSession.sampleRate != outputContext.commonFormat.mSampleRate {
                outputContext.commonFormat.mSampleRate = audioSession.sampleRate
                result = AudioUnitSetProperty(outputContext.outputNodeContext.audioUnit!,
                                              kAudioUnitProperty_StreamFormat,
                                              kAudioUnitScope_Input,
                                              0,
                                              &outputContext.commonFormat,
                                              audioStreamBasicDescriptionSize)
                warning = checkError(result, domain: "set hardware output stream format error")
                if let warning = warning {
                    delegateWarningCallback()
                }
            }
        }

        result = AudioUnitSetProperty(outputContext.converterNodeContext.audioUnit!,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &outputContext.commonFormat,
                                      audioStreamBasicDescriptionSize)
        error = checkError(result, domain: "graph set converter input format error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AudioUnitSetProperty(outputContext.converterNodeContext.audioUnit!,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      0,
                                      &outputContext.commonFormat,
                                      audioStreamBasicDescriptionSize)
        error = checkError(result, domain: "graph set converter output format error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AudioUnitSetProperty(outputContext.mixerNodeContext.audioUnit!,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &outputContext.commonFormat,
                                      audioStreamBasicDescriptionSize)
        error = checkError(result, domain: "graph set mixer input format error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AudioUnitSetProperty(outputContext.mixerNodeContext.audioUnit!,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      0,
                                      &outputContext.commonFormat,
                                      audioStreamBasicDescriptionSize)
        error = checkError(result, domain: "graph set mixer output format error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        result = AudioUnitSetProperty(outputContext.mixerNodeContext.audioUnit!,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &IRAudioManager.maxFrameSize,
                                      UInt32(MemoryLayout.size(ofValue: IRAudioManager.maxFrameSize)))
        warning = checkError(result, domain: "graph set mixer max frames per slice size error")
        if let warning = warning {
            delegateWarningCallback()
        }

        result = AUGraphInitialize(outputContext.graph!)
        error = checkError(result, domain: "graph initialize error")
        if let error = error {
            delegateErrorCallback()
            return false
        }

        return true
    }

    func renderFrames(_ numberOfFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let ioBuffers = UnsafeBufferPointer(start: &ioData.pointee.mBuffers, count: Int(ioData.pointee.mNumberBuffers))

        for buffer in ioBuffers {
            memset(buffer.mData, 0, Int(buffer.mDataByteSize))
        }

        if playing, let delegate = delegate {
            delegate.audioManager(self, outputData: _outData!, numberOfFrames: numberOfFrames, numberOfChannels: numberOfChannels)

            let numBytesPerSample = outputContext!.commonFormat.mBitsPerChannel / 8
            if numBytesPerSample == 4 {
                var zero: Float = 0.0
                for buffer in ioBuffers {
                    let numChannels = buffer.mNumberChannels
                    for j in 0..<Int(numChannels) {
                        vDSP_vsadd(_outData! + j,
                                   vDSP_Stride(numberOfChannels),
                                   &zero,
                                   buffer.mData!.assumingMemoryBound(to: Float.self),
                                   vDSP_Stride(numChannels),
                                   vDSP_Length(numberOfFrames))
                    }
                }
            } else if numBytesPerSample == 2 {
                var scale: Float = Float(INT16_MAX)
                vDSP_vsmul(_outData!, 1, &scale, _outData!, 1, vDSP_Length(numberOfFrames * numberOfChannels))

                for buffer in ioBuffers {
                    let numChannels = buffer.mNumberChannels
                    for j in 0..<Int(numChannels) {
                        vDSP_vfix16(_outData! + j,
                                    vDSP_Stride(numberOfChannels),
                                    buffer.mData!.assumingMemoryBound(to: Int16.self) + j,
                                    vDSP_Stride(numChannels),
                                    vDSP_Length(numberOfFrames))
                    }
                }
            }
        }

        return noErr
    }

    func play(withDelegate delegate: IRAudioManagerDelegate) {
        self.delegate = delegate
        play()
    }

    private func play() {
        guard !_playing,
              let graph = outputContext?.graph else { return }
        if registerAudioSession() {
            let result = AUGraphStart(graph)
            error = checkError(result, domain: "graph start error")
            if let error = error {
                delegateErrorCallback()
            } else {
                _playing = true
            }
        }
    }

    func pause() {
        guard _playing,
              let graph = outputContext?.graph else { return }
        let result = AUGraphStop(graph)
        error = checkError(result, domain: "graph stop error")
        if let error = error {
            delegateErrorCallback()
        }
        _playing = false
    }

    private func delegateErrorCallback() {
        if let error = error {
            print("IRAudioManager did error: \(error)")
        }
    }

    private func delegateWarningCallback() {
        if let warning = warning {
            print("IRAudioManager did warning: \(warning)")
        }
    }

    private func checkError(_ result: OSStatus, domain: String) -> NSError? {
        return result == noErr ? nil : NSError(domain: domain, code: Int(result), userInfo: nil)
    }

    private static var maxFrameSize = 4096
    private static let maxChan = 2
}

typealias IRAudioManagerInterruptionHandler = (_ handlerTarget: AnyObject, _ audioManager: IRAudioManager, _ type: IRAudioManagerInterruptionType, _ option: IRAudioManagerInterruptionOption) -> Void
typealias IRAudioManagerRouteChangeHandler = (_ handlerTarget: AnyObject, _ audioManager: IRAudioManager, _ reason: IRAudioManagerRouteChangeReason) -> Void

private struct IRAudioNodeContext {
    var node: AUNode = 0
    var audioUnit: AudioUnit?
}

private struct IRAudioOutputContext {
    var graph: AUGraph? = nil
    var converterNodeContext = IRAudioNodeContext()
    var mixerNodeContext = IRAudioNodeContext()
    var outputNodeContext = IRAudioNodeContext()
    var commonFormat = AudioStreamBasicDescription()
}

private func renderCallback(inRefCon: UnsafeMutableRawPointer, ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, inTimeStamp: UnsafePointer<AudioTimeStamp>, inOutputBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let audioManager = Unmanaged<IRAudioManager>.fromOpaque(inRefCon).takeUnretainedValue()
    return audioManager.renderFrames(inNumberFrames, ioData: ioData!)
}
