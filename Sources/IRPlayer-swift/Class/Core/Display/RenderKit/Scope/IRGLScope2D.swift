//
//  IRGLScope2D.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

import Foundation

class IRGLScope2D {
    var scaleX: Float
    var scaleY: Float
    var w: Int
    var h: Int
    var offsetX: Float
    var offsetY: Float
    var panDegree: Float

    init() {
        self.scaleX = 1.0
        self.scaleY = 1.0
        self.w = 0
        self.h = 0
        self.offsetX = 0.0
        self.offsetY = 0.0
        self.panDegree = 0.0
    }

    init(old: IRGLScope2D) {
        self.w = old.w
        self.h = old.h
        self.scaleX = old.scaleX
        self.scaleY = old.scaleY
        self.offsetX = old.offsetX
        self.offsetY = old.offsetY
        self.panDegree = old.panDegree
    }

    init(scaleX: Float, scaleY: Float, offsetX: Float, offsetY: Float, panDegree: Float, w: Int, h: Int) {
        self.w = w
        self.h = h
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.panDegree = panDegree
    }
}
