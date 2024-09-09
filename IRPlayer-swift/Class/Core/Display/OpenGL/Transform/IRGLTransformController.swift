//
//  IRGLTransformController.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/7.
//

import Foundation
import UIKit
import GLKit

protocol IRGLTransformControllerDelegate: AnyObject {
    func willScroll(dx: Float, dy: Float, transformController: IRGLTransformController)
    func doScrollHorizontal(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool
    func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool
    func didScroll(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController)
}

class IRGLScopeRange {
    let minLat: Float
    let maxLat: Float
    let minLng: Float
    let maxLng: Float
    let defaultLat: Float
    let defaultLng: Float

    init(minLat: Float, maxLat: Float, minLng: Float, maxLng: Float, defaultLat: Float, defaultLng: Float) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLng = minLng
        self.maxLng = maxLng
        self.defaultLat = defaultLat
        self.defaultLng = defaultLng
    }
}

class IRGLScaleRange {
    let minScaleX: Float
    let minScaleY: Float
    let maxScaleX: Float
    let maxScaleY: Float
    let defaultScaleX: Float
    let defaultScaleY: Float

    init(minScaleX: Float, minScaleY: Float, maxScaleX: Float, maxScaleY: Float, defaultScaleX: Float, defaultScaleY: Float) {
        self.minScaleX = minScaleX
        self.minScaleY = minScaleY
        self.maxScaleX = maxScaleX
        self.maxScaleY = maxScaleY
        self.defaultScaleX = defaultScaleX
        self.defaultScaleY = defaultScaleY
    }
}

class IRGLWideDegreeRange {
    let wideDegreeX: Float
    let wideDegreeY: Float

    init(wideDegreeX: Float, wideDegreeY: Float) {
        self.wideDegreeX = wideDegreeX
        self.wideDegreeY = wideDegreeY
    }
}

@objcMembers public class IRGLTransformController: NSObject {

    public struct ScrollStatus: OptionSet {
        public let rawValue: UInt

        static let none = ScrollStatus(rawValue: 0)
        static let toMaxX = ScrollStatus(rawValue: 1 << 0)
        static let toMinX = ScrollStatus(rawValue: 1 << 1)
        static let toMaxY = ScrollStatus(rawValue: 1 << 2)
        static let toMinY = ScrollStatus(rawValue: 1 << 3)
        static let fail   = ScrollStatus(rawValue: 1 << 4)

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }
    }

    enum ScrollToBounds {
        case none
        case horizontal
        case vertical
        case both
    }

    weak var delegate: IRGLTransformControllerDelegate?
    var scopeRange: IRGLScopeRange?
    var scaleRange: IRGLScaleRange?

    var defaultTransformScaleX: Float = 1.0
    var defaultTransformScaleY: Float = 1.0

    init(scopeRange: IRGLScopeRange = IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0),
         scaleRange: IRGLScaleRange = IRGLScaleRange(minScaleX: 1.0, minScaleY: 1.0, maxScaleX: 4.0, maxScaleY: 4.0, defaultScaleX: 1.0, defaultScaleY: 1.0)) {
        self.scopeRange = scopeRange
        self.scaleRange = scaleRange
        defaultTransformScaleX = scaleRange.defaultScaleX
        defaultTransformScaleY = scaleRange.defaultScaleY
    }

    func getScope() -> IRGLScope2D {
        return IRGLScope2D()
    }

    func getModelViewProjectionMatrix() -> GLKMatrix4 {
        return GLKMatrix4Identity
    }

    func setupDefaultTransform(scaleX: Float, scaleY: Float) {
        self.defaultTransformScaleX = scaleX
        self.defaultTransformScaleY = scaleY
    }

    func getDefaultTransformScale() -> CGPoint {
        return CGPoint(x: CGFloat(defaultTransformScaleX), y: CGFloat(defaultTransformScaleY))
    }

    func updateToDefault() {
        // Implement logic to update to default
    }

    func scroll(degreeX: Float, degreeY: Float) {
        // Implement logic for scrolling by degree
    }

    func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        // Implement logic to update transformation
    }

    func scroll(dx: Float, dy: Float) {
        // Implement logic for scrolling by dx, dy
    }

    func rotate(degree: Float) {
        // Implement rotation logic
    }

    func updateVertices() {
        // Implement logic to update vertices
    }

    func resetViewport(width: Int, height: Int, resetTransform: Bool) {
        // Implement viewport reset logic
    }

    func reset() {
        // Implement reset logic
    }
}

