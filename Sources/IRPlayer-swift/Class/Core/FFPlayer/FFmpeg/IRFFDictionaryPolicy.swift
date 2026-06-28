//
//  IRFFDictionaryPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import IRFFMpeg

enum IRFFDictionaryPolicy {
    static func string(fromCString cString: UnsafePointer<CChar>?) -> String? {
        guard let cString else { return nil }
        return String(validatingUTF8: cString)
    }

    static func foundationDictionary(from avDictionary: OpaquePointer?) -> [String: String]? {
        guard let avDictionary = avDictionary else { return nil }

        var dictionary: [String: String] = [:]
        var entry: UnsafeMutablePointer<AVDictionaryEntry>? = nil

        while let nextEntry = av_dict_get(avDictionary, "", entry, AV_DICT_IGNORE_SUFFIX) {
            if let keyString = string(fromCString: nextEntry.pointee.key),
               let valueString = string(fromCString: nextEntry.pointee.value) {
                dictionary[keyString] = valueString
            }
            entry = nextEntry
        }

        return dictionary.isEmpty ? nil : dictionary
    }
}
