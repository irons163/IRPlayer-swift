//
//  IRGLProgram2DFisheye2PanoFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/13.
//

import Foundation

class IRGLProgram2DFisheye2PanoFactory: IRGLProgram2DFactory {

    override func createIRGLProgram(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2D {
        return IRGLProgramFactory.createIRGLProgram2DFisheye2Pano(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
    }
}
