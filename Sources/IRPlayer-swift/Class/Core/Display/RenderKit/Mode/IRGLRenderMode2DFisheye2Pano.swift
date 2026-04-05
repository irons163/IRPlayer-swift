//
//  IRGLRenderMode2DFisheye2Pano.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

public class IRGLRenderMode2DFisheye2Pano: IRGLRenderMode {

    public override var programFactory: IRGLProgram2DFactory {
        return IRGLProgram2DFisheye2PanoFactory()
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
