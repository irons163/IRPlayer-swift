//
//  IRMetalFisheyeMeshPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

enum IRMetalFisheyeMeshPolicy {
    static func resolveParams(textureWidth: Float,
                              textureHeight: Float,
                              centerX: Float,
                              centerY: Float,
                              radius: Float) -> (textureWidth: Float, textureHeight: Float, centerX: Float, centerY: Float, radius: Float) {
        let tw = textureWidth
        let th = textureHeight
        var cx = centerX
        var cy = centerY
        var cr = radius

        if !tw.isFinite || !th.isFinite || !cx.isFinite || !cy.isFinite || !cr.isFinite || tw <= 0 || th <= 0 {
            return (0, 0, 0, 0, 0)
        }

        if cr == 0 || cx == 0 || cy == 0 || cr > tw / 2 || cr > th / 2 || cr + cx > tw || cr + cy > th {
            cx = tw / 2
            cy = th / 2
            cr = min(tw, th) / 2
        }

        return (tw, th, cx, cy, cr)
    }

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
