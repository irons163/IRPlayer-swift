//
//  IRAudioManagerPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import AVFoundation
import Foundation

enum IRAudioManagerPolicy {
    static func unsignedInteger(from value: Any?) -> UInt? {
        if let value = value as? NSNumber {
            guard IRPayloadNumber.isInteger(value) else { return nil }
            guard value.int64Value >= 0 else { return nil }
            return UInt(value.uint64Value)
        }
        if let value = value as? UInt {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt(value)
        }
        return nil
    }

    static func requiredAudioGraph(_ graph: AUGraph?, domain: String) -> Result<AUGraph, NSError> {
        guard let graph else {
            return .failure(NSError(domain: domain, code: -1, userInfo: nil))
        }
        return .success(graph)
    }

    static func requiredAudioUnit(_ audioUnit: AudioUnit?, domain: String) -> Result<AudioUnit, NSError> {
        guard let audioUnit else {
            return .failure(NSError(domain: domain, code: -1, userInfo: nil))
        }
        return .success(audioUnit)
    }

    static func renderSampleCount(numberOfFrames: UInt32, numberOfChannels: UInt32) -> Int? {
        guard numberOfFrames > 0, numberOfChannels > 0 else { return nil }

        let (sampleCount, overflow) = Int(numberOfFrames).multipliedReportingOverflow(by: Int(numberOfChannels))
        guard !overflow, sampleCount > 0 else { return nil }
        return sampleCount
    }

    static func renderSampleCount(numberOfFrames: UInt32,
                                  numberOfChannels: UInt32,
                                  maximumSampleCount: Int) -> Int? {
        guard maximumSampleCount > 0 else { return nil }
        guard let sampleCount = renderSampleCount(numberOfFrames: numberOfFrames, numberOfChannels: numberOfChannels) else {
            return nil
        }
        guard sampleCount <= maximumSampleCount else { return nil }
        return sampleCount
    }
}
