//
//  IRSensor.swift
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/12.
//  Copyright © 2022 Phil. All rights reserved.
//

import Foundation
import UIKit
import CoreMotion

class IRSensor {
    weak var targetView: IRGLView?
    weak var smoothScroll: IRSmoothScrollController?

    private var referenceAttitude: CMAttitude?
    private let manager: CMMotionManager
    private var orientation: UIInterfaceOrientation

    init() {
        self.manager = CMMotionManager()
        self.orientation = .portrait
        updateDeviceOrientation(orientation: Self.currentInterfaceOrientation())
    }

    func updateDeviceOrientation(orientation: UIInterfaceOrientation) {
        self.orientation = orientation
    }

    // MARK: - Wide Functions
    func resetUnit() -> Bool {
        stopMotionDetection()
        referenceAttitude = nil

        var lastOffsetXByDeviceMotion: CGFloat = 0
        var lastOffsetYByDeviceMotion: CGFloat = 0

        let motionQueue = OperationQueue()
        manager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            let referencePolicy = Self.referenceAttitudePolicy(hasReferenceAttitude: self.referenceAttitude != nil)
            let doScroll = referencePolicy.shouldScroll
            if referencePolicy.shouldCaptureReferenceAttitude {
                self.referenceAttitude = motion.attitude.copy() as? CMAttitude
                lastOffsetXByDeviceMotion = 0
                lastOffsetYByDeviceMotion = 0
            }

            let pitch = motion.attitude.pitch * 180.0 / .pi
            let roll = motion.attitude.roll * 180.0 / .pi

            guard let referenceAttitude = self.referenceAttitude else { return }
            motion.attitude.multiply(byInverseOf: referenceAttitude)
            let inQuat = motion.attitude.quaternion

            let inversePitch = atan2(2 * (inQuat.x * inQuat.w + inQuat.y * inQuat.z), 1 - 2 * inQuat.x * inQuat.x - 2 * inQuat.z * inQuat.z)
            let inverseRoll = atan2(2 * (inQuat.y * inQuat.w - inQuat.x * inQuat.z), 1 - 2 * inQuat.y * inQuat.y - 2 * inQuat.z * inQuat.z)

            var degreeX: CGFloat = 0
            var degreeY: CGFloat = 0

            switch self.orientation {
            case .portrait:
                if pitch < 15 {
                    self.referenceAttitude = nil
                    return
                }
                degreeX = CGFloat(inverseRoll * 180.0 / .pi)
                degreeY = CGFloat(inversePitch * 180.0 / .pi)

            case .portraitUpsideDown:
                if pitch > -15 {
                    self.referenceAttitude = nil
                    return
                }
                degreeX = CGFloat(inverseRoll * 180.0 / .pi) * -1
                degreeY = CGFloat(inversePitch * 180.0 / .pi) * -1

            case .landscapeLeft:
                if roll < 15 {
                    self.referenceAttitude = nil
                    return
                }
                degreeX = CGFloat(inversePitch * 180.0 / .pi) * -1
                degreeY = CGFloat(inverseRoll * 180.0 / .pi)

            case .landscapeRight:
                if roll > -15 {
                    self.referenceAttitude = nil
                    return
                }
                degreeX = CGFloat(inversePitch * 180.0 / .pi)
                degreeY = CGFloat(inverseRoll * 180.0 / .pi) * -1

            default:
                self.referenceAttitude = nil
                return
            }

            let newOffsetXByDeviceMotion = degreeX
            let newOffsetYByDeviceMotion = -degreeY
            let dx = Self.normalizedMotionDelta(current: newOffsetXByDeviceMotion, previous: lastOffsetXByDeviceMotion)
            let dy = newOffsetYByDeviceMotion - lastOffsetYByDeviceMotion
            lastOffsetXByDeviceMotion = newOffsetXByDeviceMotion
            lastOffsetYByDeviceMotion = newOffsetYByDeviceMotion

            DispatchQueue.main.async {
                let currentOrientation = self.targetView?.window?.windowScene?.interfaceOrientation
                    ?? Self.currentInterfaceOrientation()
                if self.orientation != currentOrientation {
                    self.updateDeviceOrientation(orientation: currentOrientation)
                    return
                }
                if doScroll {
                    guard let shift = Self.motionScrollShift(dx: dx, dy: dy) else { return }
                    self.smoothScroll?.shiftDegreeX(shift.degreeX, degreeY: shift.degreeY)
                }
            }
        }

        return true
    }

    func stopMotionDetection() {
        manager.stopDeviceMotionUpdates()
    }

    static func normalizedMotionDelta(current: CGFloat, previous: CGFloat) -> CGFloat {
        guard current.isFinite, previous.isFinite else {
            return 0
        }
        let delta = current - previous
        guard delta.isFinite else {
            return 0
        }
        if delta < -180 {
            return 360 + delta
        } else if delta > 180 {
            return delta - 360
        }
        return delta
    }

    static func motionScrollShift(dx: CGFloat, dy: CGFloat) -> (degreeX: Float, degreeY: Float)? {
        guard dx.isFinite, dy.isFinite else { return nil }
        return (Float(dx), Float(dy))
    }

    static func referenceAttitudePolicy(hasReferenceAttitude: Bool) -> (shouldCaptureReferenceAttitude: Bool, shouldScroll: Bool) {
        if hasReferenceAttitude {
            return (false, true)
        }
        return (true, false)
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let activeSceneOrientation = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation {
            return activeSceneOrientation
        }

        if let anySceneOrientation = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?
            .interfaceOrientation {
            return anySceneOrientation
        }

        return .portrait
    }
}
