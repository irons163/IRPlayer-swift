//
//  IRGLRenderModeMulti4P.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

public class IRGLRenderModeMulti4P: IRGLRenderMode {

    public override var programFactory: IRGLProgram2DFactory {
        return IRGLProgram3DFisheye4PFactory()
    }

    public override var contentMode: IRGLRenderContentMode {
        didSet {
            self.program?.contentMode = contentMode
        }
    }

    public override init() {
        super.init()
        self.shiftController.panAngle = 360
        self.shiftController.tiltAngle = 360
    }
}
