//
//  IRGLScope3D.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

import Foundation

class IRGLScope3D: IRGLScope2D {

    enum TiltType: Int {
        case unknown = 0
        case up
        case toward
        case backward
    }

    var tiltType: TiltType = .up
    var lat: Float = 0.0
    var lng: Float = 0.0

    override init() {
        super.init()
        self.tiltType = .up
        self.lat = 0.0
        self.lng = 0.0
    }

    init(old: IRGLScope3D) {
        super.init(old: old)
        self.tiltType = old.tiltType
        self.lat = old.lat
        self.lng = old.lng
    }

    init(lat: Float, lng: Float, scale: Float, tiltType: TiltType, panDegree: Float, width: Int, height: Int) {
        super.init(scaleX: scale, scaleY: scale, offsetX: 0, offsetY: 0, panDegree: panDegree, w: width, h: height)
        self.tiltType = tiltType
        self.lat = lat
        self.lng = lng
    }
}
