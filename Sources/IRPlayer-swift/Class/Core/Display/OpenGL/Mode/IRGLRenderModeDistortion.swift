//
//  IRGLRenderModeDistortion.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

class IRGLRenderModeDistortion: IRGLRenderMode {

    public override var programFactory: IRGLProgram2DFactory {
        return IRGLProgramDistortionFactory()
    }

    override var contentMode: IRGLRenderContentMode {
        didSet {
            self.program?.contentMode = contentMode
        }
    }

    override init() {
        super.init()
        self.shiftController.panAngle = 360
        self.shiftController.tiltAngle = 180
    }
}
