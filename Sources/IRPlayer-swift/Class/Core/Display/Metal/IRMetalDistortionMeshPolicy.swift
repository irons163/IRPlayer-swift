//
//  IRMetalDistortionMeshPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

enum IRMetalDistortionMeshPolicy {
    static func bufferByteLength(elementCount: Int, stride: Int) -> Int? {
        guard elementCount > 0, stride > 0 else { return nil }

        let (byteLength, overflow) = elementCount.multipliedReportingOverflow(by: stride)
        guard !overflow, byteLength > 0 else { return nil }

        return byteLength
    }

    static func indexValue(_ value: Int) -> UInt16? {
        guard value >= 0, value <= Int(UInt16.max) else { return nil }
        return UInt16(value)
    }
}
