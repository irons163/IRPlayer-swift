//
//  IRFFVideoFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation

enum IRYUVChannel: Int {
    case luma = 0
    case chromaB = 1
    case chromaR = 2
    case count = 3
}

@objcMembers public class IRFFVideoFrame: IRFFFrame {
    public var width: Int = 0
    public var height: Int = 0

    override var type: IRFFFrameType {
        return .video
    }
}
