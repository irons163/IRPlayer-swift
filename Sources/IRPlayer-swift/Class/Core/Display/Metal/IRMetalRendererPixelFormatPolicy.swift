//
//  IRMetalRendererPixelFormatPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

enum IRMetalRendererPixelFormatPolicy {
    static func rgbTextureLayout(width: Int, height: Int, linesize: Int, byteCount: Int) -> (bytesPerRow: Int, totalByteCount: Int)? {
        guard width > 0, height > 0, linesize > 0, byteCount >= 0 else { return nil }

        let (expectedBytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        guard !rowOverflow, expectedBytesPerRow > 0, linesize == expectedBytesPerRow else { return nil }

        let (totalByteCount, totalOverflow) = expectedBytesPerRow.multipliedReportingOverflow(by: height)
        guard !totalOverflow, totalByteCount > 0, byteCount >= totalByteCount else { return nil }

        return (bytesPerRow: expectedBytesPerRow, totalByteCount: totalByteCount)
    }
}

enum IRMetalRendererFish2PanoPolicy {
    static func inputsAreValid(params: IRMetalRenderer.Fish2PanoParams, texUVTextureCount: Int) -> Bool {
        guard params.fishwidth > 0,
              params.fishheight > 0,
              params.panowidth > 0,
              params.panoheight > 0,
              params.antialias > 0,
              params.offsetX.isFinite,
              texUVTextureCount > 0 else {
            return false
        }

        let antialias = Int(params.antialias)
        let (requiredTextureCount, overflow) = antialias.multipliedReportingOverflow(by: antialias)
        guard !overflow,
              requiredTextureCount > 0,
              requiredTextureCount <= 9 else {
            return false
        }

        return texUVTextureCount == requiredTextureCount
    }
}
