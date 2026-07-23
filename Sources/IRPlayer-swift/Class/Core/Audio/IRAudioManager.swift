import AVFoundation
import Foundation

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
    func audioManager(
        _ audioManager: IRAudioManager,
        outputData: UnsafeMutablePointer<Float>,
        numberOfFrames: UInt32,
        numberOfChannels: UInt32
    )
}

typealias IRAudioManagerInterruptionHandler = (
    _ handlerTarget: AnyObject,
    _ audioManager: IRAudioManager,
    _ type: IRAudioManagerInterruptionType,
    _ option: IRAudioManagerInterruptionOption
) -> Void

typealias IRAudioManagerRouteChangeHandler = (
    _ handlerTarget: AnyObject,
    _ audioManager: IRAudioManager,
    _ reason: IRAudioManagerRouteChangeReason
) -> Void

struct IRAudioHardwareInfo {
    let sampleRate: () -> Float64
    let channelCount: () -> UInt32

    static var system: IRAudioHardwareInfo {
        #if os(macOS)
        return IRAudioHardwareInfo(
            sampleRate: { 0 },
            channelCount: { 0 }
        )
        #else
        let session = AVAudioSession.sharedInstance()
        return IRAudioHardwareInfo(
            sampleRate: {
                let value = session.sampleRate
                return value.isFinite && value > 0 ? value : 0
            },
            channelCount: {
                let value = session.outputNumberOfChannels
                guard value > 0, value <= Int(UInt32.max) else { return 0 }
                return UInt32(value)
            }
        )
        #endif
    }
}

final class IRAudioEventRouter: @unchecked Sendable {
    private final class Binding {
        weak var target: AnyObject?
        let interruption: IRAudioManagerInterruptionHandler
        let routeChange: IRAudioManagerRouteChangeHandler

        init(
            target: AnyObject,
            interruption: @escaping IRAudioManagerInterruptionHandler,
            routeChange: @escaping IRAudioManagerRouteChangeHandler
        ) {
            self.target = target
            self.interruption = interruption
            self.routeChange = routeChange
        }
    }

    private let lock = NSLock()
    private var binding: Binding?

    func setTarget(
        _ target: AnyObject,
        interruption: @escaping IRAudioManagerInterruptionHandler,
        routeChange: @escaping IRAudioManagerRouteChangeHandler
    ) {
        lock.lock()
        binding = Binding(
            target: target,
            interruption: interruption,
            routeChange: routeChange
        )
        lock.unlock()
    }

    func removeTarget(_ target: AnyObject) {
        lock.lock()
        if binding?.target === target || binding?.target == nil {
            binding = nil
        }
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        binding = nil
        lock.unlock()
    }

    func deliver(
        _ event: (
            type: IRAudioManagerInterruptionType,
            option: IRAudioManagerInterruptionOption
        ),
        manager: IRAudioManager
    ) {
        lock.lock()
        let delivery = binding.flatMap { binding -> (
            AnyObject,
            IRAudioManagerInterruptionHandler
        )? in
            guard let target = binding.target else {
                self.binding = nil
                return nil
            }
            return (target, binding.interruption)
        }
        lock.unlock()
        if let (target, handler) = delivery {
            handler(target, manager, event.type, event.option)
        }
    }

    func deliver(
        _ reason: IRAudioManagerRouteChangeReason,
        manager: IRAudioManager
    ) {
        lock.lock()
        let delivery = binding.flatMap { binding -> (
            AnyObject,
            IRAudioManagerRouteChangeHandler
        )? in
            guard let target = binding.target else {
                self.binding = nil
                return nil
            }
            return (target, binding.routeChange)
        }
        lock.unlock()
        if let (target, handler) = delivery {
            handler(target, manager, reason)
        }
    }
}

final class IRAudioManager: NSObject {
    let graphSession: IRAudioGraphSession

    private let notificationCenter: NotificationCenter
    private let hardwareInfo: IRAudioHardwareInfo
    private let eventRouter = IRAudioEventRouter()
    private var observerTokens: [NSObjectProtocol] = []

    override convenience init() {
        self.init(
            graphSession: IRAudioGraphSession(),
            hardwareInfo: .system,
            notificationCenter: .default
        )
    }

    init(
        graphSession: IRAudioGraphSession,
        hardwareInfo: IRAudioHardwareInfo,
        notificationCenter: NotificationCenter
    ) {
        self.graphSession = graphSession
        self.hardwareInfo = hardwareInfo
        self.notificationCenter = notificationCenter
        super.init()
        installObservers()
    }

    deinit {
        observerTokens.forEach(notificationCenter.removeObserver)
        eventRouter.removeAll()
        graphSession.close()
    }

    var diagnostics: IRAudioGraphSession.Diagnostics {
        graphSession.diagnostics
    }

    var volume: Float {
        get { graphSession.volume() }
        set { graphSession.setVolume(newValue) }
    }

    var playing: Bool {
        graphSession.isRunning
    }

    var delegate: IRAudioManagerDelegate? {
        graphSession.renderContext.currentDelegate
    }

    var samplingRate: Float64 {
        let graphRate = graphSession.samplingRate
        if graphRate.isFinite, graphRate > 0 {
            return graphRate
        }
        return hardwareInfo.sampleRate()
    }

    var numberOfChannels: UInt32 {
        let graphChannels = graphSession.numberOfChannels
        return graphChannels > 0 ? graphChannels : hardwareInfo.channelCount()
    }

    func setHandlerTarget(
        _ handlerTarget: AnyObject,
        interruption: @escaping IRAudioManagerInterruptionHandler,
        routeChange: @escaping IRAudioManagerRouteChangeHandler
    ) {
        eventRouter.setTarget(
            handlerTarget,
            interruption: interruption,
            routeChange: routeChange
        )
    }

    func removeHandlerTarget(_ handlerTarget: AnyObject) {
        eventRouter.removeTarget(handlerTarget)
    }

    @discardableResult
    func registerAudioSession() -> Bool {
        graphSession.prepare(
            preferredSampleRate: hardwareInfo.sampleRate()
        )
    }

    func unregisterAudioSession() {
        graphSession.reset()
    }

    @discardableResult
    func play(withDelegate delegate: IRAudioManagerDelegate) -> Bool {
        graphSession.start(
            owner: self,
            delegate: delegate,
            preferredSampleRate: hardwareInfo.sampleRate()
        )
    }

    func pause() {
        graphSession.pause()
    }

    func renderFrames(
        _ numberOfFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        graphSession.renderFrames(numberOfFrames, ioData: ioData)
    }

    static func unsignedInteger(from value: Any?) -> UInt? {
        if let value = value as? NSNumber {
            guard IRPayloadNumber.isInteger(value),
                  value.int64Value >= 0 else {
                return nil
            }
            return UInt(value.uint64Value)
        }
        if let value = value as? UInt {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt(value)
        }
        return nil
    }

    static func interruptionEvent(
        typeValue: Any?,
        optionValue: Any?
    ) -> (
        type: IRAudioManagerInterruptionType,
        option: IRAudioManagerInterruptionOption
    )? {
        guard let rawType = unsignedInteger(from: typeValue),
              let avType = AVAudioSession.InterruptionType(
                rawValue: rawType
              ) else {
            return nil
        }

        let type: IRAudioManagerInterruptionType =
            avType == .ended ? .ended : .begin
        let option: IRAudioManagerInterruptionOption
        if let rawOption = unsignedInteger(from: optionValue),
           rawOption ==
            AVAudioSession.InterruptionOptions.shouldResume.rawValue {
            option = .shouldResume
        } else {
            option = .none
        }
        return (type, option)
    }

    static func routeChangeReason(
        from value: Any?
    ) -> IRAudioManagerRouteChangeReason? {
        guard let rawReason = unsignedInteger(from: value),
              let reason = AVAudioSession.RouteChangeReason(
                rawValue: rawReason
              ),
              reason == .oldDeviceUnavailable else {
            return nil
        }
        return .oldDeviceUnavailable
    }

    static func renderSampleCount(
        numberOfFrames: UInt32,
        numberOfChannels: UInt32
    ) -> Int? {
        IRAudioRenderContext.sampleCount(
            numberOfFrames: numberOfFrames,
            numberOfChannels: numberOfChannels
        )
    }

    static func renderSampleCount(
        numberOfFrames: UInt32,
        numberOfChannels: UInt32,
        maximumSampleCount: Int
    ) -> Int? {
        IRAudioRenderContext.sampleCount(
            numberOfFrames: numberOfFrames,
            numberOfChannels: numberOfChannels,
            maximumSampleCount: maximumSampleCount
        )
    }

    private func installObservers() {
        #if !os(macOS)
        observerTokens = [
            notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            },
            notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            }
        ]
        #endif
    }

    private func handleInterruption(_ notification: Notification) {
        guard let event = Self.interruptionEvent(
            typeValue:
                notification.userInfo?[AVAudioSessionInterruptionTypeKey],
            optionValue:
                notification.userInfo?[AVAudioSessionInterruptionOptionKey]
        ) else {
            return
        }
        eventRouter.deliver(event, manager: self)
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let reason = Self.routeChangeReason(
            from:
                notification.userInfo?[AVAudioSessionRouteChangeReasonKey]
        ) else {
            return
        }
        eventRouter.deliver(reason, manager: self)
    }
}
