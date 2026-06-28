//
//  IRGLProjectionEquirectangularPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRGLProjectionEquirectangularPolicy {

    static func isValidGeometry(tw: Float, th: Float, cr: Float, cx: Float, cy: Float) -> Bool {
        guard tw.isFinite,
              th.isFinite,
              cr.isFinite,
              cx.isFinite,
              cy.isFinite,
              cr > 0,
              cx > 0,
              cy > 0,
              tw >= cr,
              th >= cr,
              cx + cr <= tw,
              cy + cr <= th else {
            return false
        }
        return true
    }

    static func maxItem(in array: UnsafeMutablePointer<Int>?, size: Int) -> Int? {
        guard let array, size > 0 else { return nil }

        var max = array[0]
        for i in 1..<size {
            if array[i] > max {
                max = array[i]
            }
        }

        return max
    }

    static func bufferPlan(slices: Int,
                           indicesPerVertex: Int) -> IRGLProjectionEquirectangular.BufferPlan? {
        guard slices > 0, indicesPerVertex > 0 else { return nil }

        let (iMax, iMaxOverflow) = slices.addingReportingOverflow(1)
        guard !iMaxOverflow else { return nil }

        guard let vertexCount = elementCount(baseCount: iMax, components: iMax),
              let vertexCapacity = elementCount(baseCount: vertexCount, components: 3),
              let vectorCapacity = elementCount(baseCount: vertexCount, components: 2),
              let sliceSquareCount = elementCount(baseCount: slices, components: slices),
              let totalIndices = elementCount(baseCount: sliceSquareCount, components: 6) else {
            return nil
        }

        return IRGLProjectionEquirectangular.BufferPlan(iMax: iMax,
                                                        vertexCount: vertexCount,
                                                        vertexCapacity: vertexCapacity,
                                                        vectorCapacity: vectorCapacity,
                                                        totalIndices: totalIndices)
    }

    static func elementCount(baseCount: Int, components: Int) -> Int? {
        guard baseCount > 0, components > 0 else { return nil }

        let (count, overflow) = baseCount.multipliedReportingOverflow(by: components)
        guard !overflow, count > 0 else { return nil }

        return count
    }

    static func byteCount(elementCount: Int, stride: Int) -> Int? {
        guard elementCount > 0, stride > 0 else { return nil }

        let (count, overflow) = elementCount.multipliedReportingOverflow(by: stride)
        guard !overflow, count > 0 else { return nil }

        return count
    }

    static func indexValue(_ value: Int) -> Int16? {
        guard value >= Int(Int16.min), value <= Int(Int16.max) else { return nil }
        return Int16(value)
    }
}
