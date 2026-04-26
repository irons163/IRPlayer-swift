//
//  IRGLProgram3DFisheye4PFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/13.
//

import Foundation

class IRGLProgram3DFisheye4PFactory: IRGLProgram2DFactory {

    override func createIRGLProgram(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2D {
        return IRGLProgramFactory.createIRGLProgram3DFisheye4P(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)!
    }
}
