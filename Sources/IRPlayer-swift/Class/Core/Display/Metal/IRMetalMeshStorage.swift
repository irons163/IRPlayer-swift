//
//  IRMetalMeshStorage.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

enum IRMetalMeshStorage {
    static func byteLength(
        elementCount: Int,
        stride: Int
    ) -> Int? {
        guard elementCount > 0, stride > 0 else { return nil }
        let (byteLength, overflow) =
            elementCount.multipliedReportingOverflow(
                by: stride
            )
        return !overflow && byteLength > 0
            ? byteLength
            : nil
    }

    static func index(_ value: Int) -> UInt16? {
        UInt16(exactly: value)
    }
}
