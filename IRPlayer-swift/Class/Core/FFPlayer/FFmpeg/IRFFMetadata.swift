//
//  IRFFMetadata.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

import Foundation

struct AVDictionary {
    var rawPointer: OpaquePointer?

    init(rawPointer: OpaquePointer?) {
        self.rawPointer = rawPointer
    }
}

class IRFFMetadata {
    var language: String
    var BPS: Int64
    var duration: String
    var numberOfBytes: Int64
    var numberOfFrames: Int64

    init(avDictionary: AVDictionary) {
        let dic = IRFFFoundationBrigeOfAVDictionary(avDictionary.rawPointer)
        self.language = dic?["language"] as? String ?? ""
        self.BPS = (dic?["BPS"] as? NSNumber)?.int64Value ?? 0
        self.duration = dic?["DURATION"] as? String ?? ""
        self.numberOfBytes = (dic?["NUMBER_OF_BYTES"] as? NSNumber)?.int64Value ?? 0
        self.numberOfFrames = (dic?["NUMBER_OF_FRAMES"] as? NSNumber)?.int64Value ?? 0
    }

    static func metadata(with avDictionary: AVDictionary) -> IRFFMetadata {
        return IRFFMetadata(avDictionary: avDictionary)
    }
}
