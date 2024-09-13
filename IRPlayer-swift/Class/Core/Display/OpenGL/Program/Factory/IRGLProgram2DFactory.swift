//
//  IRGLProgram2DFactory.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/13.
//

import Foundation

public class IRGLProgram2DFactory: NSObject {

    func createIRGLProgram(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) -> IRGLProgram2D {
        return IRGLProgramFactory.createIRGLProgram2D(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
    }
}

