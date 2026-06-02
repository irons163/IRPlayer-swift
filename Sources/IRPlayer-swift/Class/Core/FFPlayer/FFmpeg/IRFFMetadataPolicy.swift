//
//  IRFFMetadataPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRFFMetadataPolicy {
    static func int64Value(_ value: Any?) -> Int64 {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return 0 }

            let doubleValue = value.doubleValue
            guard doubleValue.isFinite,
                  doubleValue.rounded(.towardZero) == doubleValue,
                  doubleValue >= Double(Int64.min),
                  doubleValue <= Double(Int64.max) else {
                return 0
            }

            return value.int64Value
        }
        if let value = value as? String {
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }
}
