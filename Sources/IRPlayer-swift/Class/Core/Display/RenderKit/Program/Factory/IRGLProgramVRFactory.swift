//
//  IRGLProgramVRFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/13.
//

import Foundation

class IRGLProgramVRFactory: IRGLProgram2DFactory {

    override func createIRGLProgram(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2D {
        return IRGLProgramFactory.createIRGLProgramVR(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
    }
}
