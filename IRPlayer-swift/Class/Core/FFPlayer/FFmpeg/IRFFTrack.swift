//
//  IRFFTrack.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/21.
//

import Foundation

// Enum for track type
enum IRFFTrackType: UInt {
    case video = 0
    case audio
    case subtitle
}

// Class for track
class IRFFTrack {
    var index: Int
    var type: IRFFTrackType
    var metadata: IRFFMetadata?

    init(index: Int, type: IRFFTrackType, metadata: IRFFMetadata? = nil) {
        self.index = index
        self.type = type
        self.metadata = metadata
    }
}
