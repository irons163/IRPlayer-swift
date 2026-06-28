//
//  IRGLFish2PanoShaderParamsPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import Foundation

enum IRGLFish2PanoShaderParamsPolicy {
    private static let degreesToRadians: GLfloat = Float.pi / 180.0

    static func outputSize(forTextureWidth textureWidth: Int, height textureHeight: Int) -> (width: Int, height: Int)? {
        guard textureWidth > 0, textureHeight > 0 else { return nil }

        guard let outputWidth = IRGLShaderParamsPolicy.boundedGLint(from: 1.422222222222222 * Double(textureWidth)) else { return nil }
        let vapertureRadians = Double(60.0 * degreesToRadians)
        let halfVaperture = 0.5 * vapertureRadians
        let deltaLongitudeRadians = 0.5 * Double(360.0 * degreesToRadians)
        guard let outputHeight = IRGLShaderParamsPolicy.boundedGLint(from: Double(outputWidth) * tan(halfVaperture) / deltaLongitudeRadians) else { return nil }
        guard outputWidth > 0, outputHeight > 0 else { return nil }
        return (Int(outputWidth), Int(outputHeight))
    }

    static func pixelMapTextureCount(antialias: GLint) -> Int? {
        guard antialias > 0 else { return nil }

        let antialiasCount = Int(antialias)
        let (textureCount, overflow) = antialiasCount.multipliedReportingOverflow(by: antialiasCount)
        guard !overflow, textureCount > 0, textureCount <= Int(Int32.max) else { return nil }
        return textureCount
    }

    static func pixelMapCapacity(outputWidth: GLint, outputHeight: GLint) -> Int? {
        guard outputWidth > 0, outputHeight > 0 else { return nil }

        let (pixelCount, pixelCountOverflow) = Int(outputWidth).multipliedReportingOverflow(by: Int(outputHeight))
        guard !pixelCountOverflow else { return nil }

        let (capacity, capacityOverflow) = pixelCount.multipliedReportingOverflow(by: 2)
        guard !capacityOverflow, capacity > 0, capacity <= Int(Int32.max) else { return nil }
        return capacity
    }

    static func pixelMapUVOffset(outputWidth: GLint, outputHeight: GLint, x: Int, y: Int) -> Int? {
        guard outputWidth > 0, outputHeight > 0, x >= 0, y >= 0 else { return nil }

        let width = Int(outputWidth)
        let height = Int(outputHeight)
        guard x < width, y < height else { return nil }
        guard pixelMapCapacity(outputWidth: outputWidth, outputHeight: outputHeight) != nil else { return nil }

        let (rowOffset, rowOffsetOverflow) = width.multipliedReportingOverflow(by: y)
        guard !rowOffsetOverflow else { return nil }

        let (pixelIndex, pixelIndexOverflow) = rowOffset.addingReportingOverflow(x)
        guard !pixelIndexOverflow else { return nil }

        let (uvOffset, uvOffsetOverflow) = pixelIndex.multipliedReportingOverflow(by: 2)
        guard !uvOffsetOverflow else { return nil }
        return uvOffset
    }

    static func shouldPublishPixelMap(jobGeneration: Int, currentGeneration: Int) -> Bool {
        jobGeneration == currentGeneration
    }
}
