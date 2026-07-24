//
//  IRFFMetadata.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

import Foundation

struct IRFFMetadata: Equatable {
    let language: String
    let BPS: Int64
    let duration: String
    let numberOfBytes: Int64
    let numberOfFrames: Int64

    init(avDictionary: OpaquePointer?) {
        self.init(
            dictionary:
                IRFFDictionary.values(
                    from: avDictionary
                ) ?? [:]
        )
    }

    init(dictionary: [String: Any]) {
        language = dictionary["language"] as? String ?? ""
        BPS = Self.int64Value(dictionary["BPS"])
        duration = dictionary["DURATION"] as? String ?? ""
        numberOfBytes = Self.int64Value(
            dictionary["NUMBER_OF_BYTES"]
        )
        numberOfFrames = Self.int64Value(
            dictionary["NUMBER_OF_FRAMES"]
        )
    }

    static func int64Value(_ value: Any?) -> Int64 {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value)
                    != CFBooleanGetTypeID() else {
                return 0
            }

            let objectType = String(
                cString: value.objCType
            )
            guard objectType == "f"
                    || objectType == "d" else {
                return Int64(value.stringValue) ?? 0
            }

            let doubleValue = value.doubleValue
            guard doubleValue.isFinite,
                  doubleValue.rounded(.towardZero)
                    == doubleValue,
                  doubleValue
                    >= -9_223_372_036_854_775_808,
                  doubleValue
                    < 9_223_372_036_854_775_808 else {
                return 0
            }
            return Int64(doubleValue)
        }
        if let value = value as? String {
            return Int64(
                value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ) ?? 0
        }
        return 0
    }
}
