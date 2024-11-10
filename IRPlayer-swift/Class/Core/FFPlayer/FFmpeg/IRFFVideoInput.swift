//
//  IRFFVideoInput.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

import Foundation

public class IRFFVideoInput {
    var videoOutput: IRFFDecoderVideoOutput?

    func updateFrame(_ input: IRFFVideoFrame) {
        videoOutput?.decoder?(nil, renderVideoFrame: input)
    }

    func setVideoOutput(_ videoOutput: IRFFDecoderVideoOutput) {
        self.videoOutput = videoOutput
    }
}
