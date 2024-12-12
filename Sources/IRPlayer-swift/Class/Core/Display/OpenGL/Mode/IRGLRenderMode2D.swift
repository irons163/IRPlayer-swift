//
//  IRGLRenderMode2D.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/17.
//

import Foundation

public class IRGLRenderMode2D: IRGLRenderMode {

    public override var programFactory: IRGLProgram2DFactory {
        return IRGLProgram2DFactory()
    }

    override var defaultScale: Float {
        didSet {
            self.program?.setDefaultScale(defaultScale)
        }
    }

    public override var contentMode: IRGLRenderContentMode {
        didSet {
            self.program?.contentMode = contentMode
        }
    }
}
