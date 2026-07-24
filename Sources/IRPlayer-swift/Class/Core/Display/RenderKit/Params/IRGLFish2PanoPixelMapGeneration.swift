//
//  IRGLFish2PanoPixelMapGeneration.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation

struct IRGLFish2PanoPixelMapDiagnostics: Equatable {
    let requestGeneration: Int
    let outputWidth: Int
    let outputHeight: Int
    let antialias: Int
    let textureCount: Int
    let elementCountPerTexture: Int
}

final class IRGLFish2PanoPixelMapGeneration:
    @unchecked Sendable
{
    let requestGeneration: Int
    let outputWidth: Int
    let outputHeight: Int
    let antialias: Int
    let textureCount: Int
    let elementCountPerTexture: Int

    private let maps: [[GLfloat]]

    init?(
        requestGeneration: Int,
        outputWidth: Int,
        outputHeight: Int,
        antialias: Int,
        maps: [[GLfloat]]
    ) {
        guard requestGeneration > 0,
              let textureCount = Self.textureCount(
                  antialias: antialias
              ),
              let elementCount = Self.elementCount(
                  outputWidth: outputWidth,
                  outputHeight: outputHeight
              ),
              maps.count == textureCount,
              maps.allSatisfy({
                  $0.count == elementCount
              }) else {
            return nil
        }

        self.requestGeneration = requestGeneration
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.antialias = antialias
        self.textureCount = textureCount
        elementCountPerTexture = elementCount
        self.maps = maps
    }

    var diagnostics: IRGLFish2PanoPixelMapDiagnostics {
        IRGLFish2PanoPixelMapDiagnostics(
            requestGeneration: requestGeneration,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            antialias: antialias,
            textureCount: textureCount,
            elementCountPerTexture: elementCountPerTexture
        )
    }

    func withUnsafeMapBuffer<Result>(
        at index: Int,
        _ body: (UnsafeBufferPointer<GLfloat>) throws -> Result
    ) rethrows -> Result? {
        guard maps.indices.contains(index) else {
            return nil
        }
        return try maps[index].withUnsafeBufferPointer(body)
    }

    static func outputSize(
        forTextureWidth textureWidth: Int,
        height textureHeight: Int
    ) -> (width: Int, height: Int)? {
        guard textureWidth > 0, textureHeight > 0 else {
            return nil
        }

        guard let outputWidth = IRGLShaderParams.boundedGLint(
            from: 1.422222222222222 * Double(textureWidth)
        ) else {
            return nil
        }
        let vapertureRadians = Double(
            60.0 * GLfloat.pi / 180.0
        )
        let halfVaperture = 0.5 * vapertureRadians
        let deltaLongitudeRadians = 0.5
            * Double(360.0 * GLfloat.pi / 180.0)
        guard let outputHeight = IRGLShaderParams.boundedGLint(
            from: Double(outputWidth)
                * tan(halfVaperture)
                / deltaLongitudeRadians
        ),
        outputWidth > 0,
        outputHeight > 0 else {
            return nil
        }
        return (
            width: Int(outputWidth),
            height: Int(outputHeight)
        )
    }

    static func textureCount(antialias: Int) -> Int? {
        guard antialias > 0 else {
            return nil
        }
        let (textureCount, overflow) =
            antialias.multipliedReportingOverflow(
                by: antialias
            )
        guard !overflow,
              textureCount > 0,
              textureCount <= Int(Int32.max) else {
            return nil
        }
        return textureCount
    }

    static func elementCount(
        outputWidth: Int,
        outputHeight: Int
    ) -> Int? {
        guard outputWidth > 0, outputHeight > 0 else {
            return nil
        }
        let (pixelCount, pixelOverflow) =
            outputWidth.multipliedReportingOverflow(
                by: outputHeight
            )
        guard !pixelOverflow else {
            return nil
        }
        let (elementCount, elementOverflow) =
            pixelCount.multipliedReportingOverflow(by: 2)
        guard !elementOverflow,
              elementCount > 0,
              elementCount <= Int(Int32.max) else {
            return nil
        }
        return elementCount
    }

    static func uvOffset(
        outputWidth: Int,
        outputHeight: Int,
        x: Int,
        y: Int
    ) -> Int? {
        guard x >= 0,
              y >= 0,
              x < outputWidth,
              y < outputHeight,
              elementCount(
                  outputWidth: outputWidth,
                  outputHeight: outputHeight
              ) != nil else {
            return nil
        }
        let (rowOffset, rowOverflow) =
            outputWidth.multipliedReportingOverflow(by: y)
        guard !rowOverflow else {
            return nil
        }
        let (pixelIndex, pixelOverflow) =
            rowOffset.addingReportingOverflow(x)
        guard !pixelOverflow else {
            return nil
        }
        let (uvOffset, uvOverflow) =
            pixelIndex.multipliedReportingOverflow(by: 2)
        guard !uvOverflow else {
            return nil
        }
        return uvOffset
    }
}
