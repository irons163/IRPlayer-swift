//
//  IRSensor.swift
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/12.
//  Copyright © 2022 Phil. All rights reserved.
//

import Foundation
import UIKit

struct IRSensorDiagnostics: Equatable {
    let phase: IRSensorMotionPhase
    let generation: UInt64
    let hasReferenceQuaternion: Bool
    let orientation: UIInterfaceOrientation
    let previousOffsetX: CGFloat
    let previousOffsetY: CGFloat
    let hasTargetView: Bool
    let hasSmoothScroll: Bool
}

struct IRSensorDependencies {
    let motionDriver: any IRSensorMotionDriving
    let callbackQueue: OperationQueue
    let currentOrientation: () -> UIInterfaceOrientation
    let deliverOnMain: (@escaping () -> Void) -> Void
    let applyShift:
        (IRSmoothScrollController, Float, Float) -> Void

    static func system() -> IRSensorDependencies {
        let callbackQueue = OperationQueue()
        callbackQueue.name =
            "com.irons163.IRPlayer.sensor.motion"
        callbackQueue.maxConcurrentOperationCount = 1
        callbackQueue.qualityOfService = .userInteractive
        return IRSensorDependencies(
            motionDriver: IRSystemSensorMotionDriver(),
            callbackQueue: callbackQueue,
            currentOrientation: {
                IRSensor.currentInterfaceOrientation()
            },
            deliverOnMain: {
                work in
                if Thread.isMainThread {
                    work()
                } else {
                    DispatchQueue.main.async(execute: work)
                }
            },
            applyShift: {
                smoothScroll,
                degreeX,
                degreeY in
                smoothScroll.shiftDegreeX(
                    degreeX,
                    degreeY: degreeY
                )
            }
        )
    }
}

class IRSensor: @unchecked Sendable {
    private let mutationLock = NSLock()
    private let dependencies: IRSensorDependencies
    private let motionSession: IRSensorMotionSession

    private weak var storedTargetView: IRGLView?
    private weak var storedSmoothScroll:
        IRSmoothScrollController?

    convenience init() {
        self.init(dependencies: .system())
    }

    init(dependencies: IRSensorDependencies) {
        self.dependencies = dependencies
        motionSession = IRSensorMotionSession(
            orientation: Self.readCurrentOrientation(
                using: dependencies.currentOrientation
            )
        )
    }

    deinit {
        stopMotionDetection()
        dependencies.callbackQueue.cancelAllOperations()
    }

    var targetView: IRGLView? {
        get {
            withMutation { storedTargetView }
        }
        set {
            withMutation {
                storedTargetView = newValue
            }
        }
    }

    var smoothScroll: IRSmoothScrollController? {
        get {
            withMutation { storedSmoothScroll }
        }
        set {
            withMutation {
                storedSmoothScroll = newValue
            }
        }
    }

    var diagnostics: IRSensorDiagnostics {
        withMutation {
            let motion = motionSession.snapshot
            return IRSensorDiagnostics(
                phase: motion.phase,
                generation: motion.generation,
                hasReferenceQuaternion:
                    motion.hasReferenceQuaternion,
                orientation: motion.orientation,
                previousOffsetX: motion.previousOffsetX,
                previousOffsetY: motion.previousOffsetY,
                hasTargetView: storedTargetView != nil,
                hasSmoothScroll:
                    storedSmoothScroll != nil
            )
        }
    }

    func updateDeviceOrientation(
        orientation: UIInterfaceOrientation
    ) {
        withMutation {
            motionSession.updateOrientation(orientation)
        }
    }

    @discardableResult
    func resetUnit() -> Bool {
        let currentOrientation = Thread.isMainThread
            ? dependencies.currentOrientation()
            : nil
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let requestGeneration =
                motionSession.prepareRestart(
                    orientation: currentOrientation
                ) else {
            dependencies.motionDriver
                .stopDeviceMotionUpdates()
            return false
        }

        dependencies.motionDriver.stopDeviceMotionUpdates()
        guard dependencies.motionDriver
                .isDeviceMotionAvailable,
              motionSession.activate(
                  generation: requestGeneration
              ) else {
            return false
        }

        let didStart = dependencies.motionDriver
            .startDeviceMotionUpdates(
                to: dependencies.callbackQueue
            ) {
                [weak self] sample in
                self?.process(
                    sample,
                    generation: requestGeneration
                )
            }
        guard didStart else {
            motionSession.deactivate(
                generation: requestGeneration
            )
            dependencies.motionDriver
                .stopDeviceMotionUpdates()
            return false
        }
        return true
    }

    func stopMotionDetection() {
        mutationLock.lock()
        motionSession.stop()
        dependencies.motionDriver.stopDeviceMotionUpdates()
        mutationLock.unlock()
    }

    fileprivate static func currentInterfaceOrientation()
        -> UIInterfaceOrientation
    {
        if let activeSceneOrientation =
                UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: {
                        $0.activationState
                            == .foregroundActive
                    })?
                    .interfaceOrientation {
            return activeSceneOrientation
        }
        if let anySceneOrientation =
                UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?
                    .interfaceOrientation {
            return anySceneOrientation
        }
        return .portrait
    }

    private func process(
        _ sample: IRSensorMotionSample,
        generation requestGeneration: UInt64
    ) {
        guard let shift = motionSession.process(
            sample,
            generation: requestGeneration
        ) else {
            return
        }
        dependencies.deliverOnMain {
            [weak self] in
            self?.deliver(shift)
        }
    }

    private func deliver(_ shift: IRSensorMotionShift) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let currentOrientation =
            storedTargetView?
                .window?
                .windowScene?
                .interfaceOrientation
            ?? dependencies.currentOrientation()
        guard motionSession.admitsDelivery(
            generation: shift.generation,
            expectedOrientation:
                shift.expectedOrientation,
            currentOrientation: currentOrientation
        ),
        let smoothScroll = storedSmoothScroll else {
            return
        }
        dependencies.applyShift(
            smoothScroll,
            shift.degreeX,
            shift.degreeY
        )
    }

    private func withMutation<Result>(
        _ body: () throws -> Result
    ) rethrows -> Result {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        return try body()
    }

    private static func readCurrentOrientation(
        using provider: () -> UIInterfaceOrientation
    ) -> UIInterfaceOrientation {
        if Thread.isMainThread {
            return provider()
        }
        return DispatchQueue.main.sync(execute: provider)
    }
}
