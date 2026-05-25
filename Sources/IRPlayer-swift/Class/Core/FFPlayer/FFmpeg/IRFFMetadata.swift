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

    convenience init(avDictionary: AVDictionary) {
        let dic = IRFFFoundationBrigeOfAVDictionary(avDictionary.rawPointer)
        self.init(dictionary: dic ?? [:])
    }

    init(dictionary: [String: Any]) {
        self.language = dictionary["language"] as? String ?? ""
        self.BPS = Self.int64Value(dictionary["BPS"])
        self.duration = dictionary["DURATION"] as? String ?? ""
        self.numberOfBytes = Self.int64Value(dictionary["NUMBER_OF_BYTES"])
        self.numberOfFrames = Self.int64Value(dictionary["NUMBER_OF_FRAMES"])
    }

    static func metadata(with avDictionary: AVDictionary) -> IRFFMetadata {
        return IRFFMetadata(avDictionary: avDictionary)
    }

    private static func int64Value(_ value: Any?) -> Int64 {
        if let value = value as? NSNumber {
            return value.int64Value
        }
        if let value = value as? String {
            return Int64(value) ?? 0
        }
        return 0
    }
}
