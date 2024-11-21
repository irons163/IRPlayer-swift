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
        self.orientation = UIApplication.shared.statusBarOrientation
        updateDeviceOrientation(orientation: self.orientation)
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

            var doScroll = true
            if self.referenceAttitude == nil {
                print("referenceAttitude nil")
                self.referenceAttitude = motion.attitude.copy() as? CMAttitude
                lastOffsetXByDeviceMotion = 0
                lastOffsetYByDeviceMotion = 0
                doScroll = false
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
            var dx = newOffsetXByDeviceMotion - lastOffsetXByDeviceMotion
            var dy = newOffsetYByDeviceMotion - lastOffsetYByDeviceMotion
            lastOffsetXByDeviceMotion = newOffsetXByDeviceMotion
            lastOffsetYByDeviceMotion = newOffsetYByDeviceMotion

            if dx < -180 {
                dx = 360 + dx
            } else if dx > 180 {
                dx = dx - 360
            }

            DispatchQueue.main.async {
                if self.orientation != UIApplication.shared.statusBarOrientation {
                    self.updateDeviceOrientation(orientation: UIApplication.shared.statusBarOrientation)
                    return
                }
                if doScroll {
                    print("scrollBy dx: \(dx * UIScreen.main.scale), dy: \(dy * UIScreen.main.scale)")
                    self.smoothScroll?.shiftDegreeX(Float(dx), degreeY: Float(dy))
                }
            }
        }

        return true
    }

    func stopMotionDetection() {
        manager.stopDeviceMotionUpdates()
    }
}
