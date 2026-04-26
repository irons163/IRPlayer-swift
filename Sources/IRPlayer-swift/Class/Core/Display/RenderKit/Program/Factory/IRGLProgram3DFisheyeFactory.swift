//
//  IRGLProgram3DFisheyeFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/13.
//

import Foundation

class IRGLProgram3DFisheyeFactory: IRGLProgram2DFactory {

    override func createIRGLProgram(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2D {
        return IRGLProgramFactory.createIRGLProgram3DFisheye(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)!
    }
}
