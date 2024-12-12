//
//  IRGLRenderMode3DFisheye.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

public class IRGLRenderMode3DFisheye: IRGLRenderMode {

    public override var programFactory: IRGLProgram2DFactory {
        return IRGLProgram3DFisheyeFactory()
    }

    public override var contentMode: IRGLRenderContentMode {
        didSet {
            self.program?.contentMode = contentMode
        }
    }

    public override init() {
        super.init()
        self.shiftController.panAngle = 180
        self.shiftController.tiltAngle = 360
    }
}
