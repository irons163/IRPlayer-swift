//
//  IRGLProgram2DPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import CoreGraphics
import Foundation

enum IRGLProgram2DPolicy {

    static func viewportSize(from viewportRange: CGRect) -> (width: Int, height: Int)? {
        let width = viewportRange.width
        let height = viewportRange.height
        guard width.isFinite,
              height.isFinite,
              width >= 0,
              height >= 0,
              width <= CGFloat(Int.max),
              height <= CGFloat(Int.max) else {
            return nil
        }

        return (Int(width), Int(height))
    }

    static func scrollToBounds(for status: IRGLTransformController.ScrollStatus) -> IRGLTransformController.ScrollToBounds {
        let didScrollToBoundsHorizontal = status.contains(.toMaxX) || status.contains(.toMinX)
        let didScrollToBoundsVertical = status.contains(.toMaxY) || status.contains(.toMinY)

        if didScrollToBoundsHorizontal && didScrollToBoundsVertical {
            return .both
        } else if didScrollToBoundsHorizontal {
            return .horizontal
        } else if didScrollToBoundsVertical {
            return .vertical
        } else {
            return .none
        }
    }

    static func outputScaleDecision(
        outputWidth: Int,
        outputHeight: Int,
        viewportWidth: Int,
        viewportHeight: Int,
        contentMode: IRGLRenderContentMode,
        shouldUpdateToDefaultWhenOutputSizeChanged: Bool
    ) -> (scaleX: Float, scaleY: Float, shouldUpdateToDefault: Bool)? {
        let width = Double(outputWidth)
        let height = Double(outputHeight)
        let viewportWidth = Double(viewportWidth)
        let viewportHeight = Double(viewportHeight)
        guard width > 0, height > 0, viewportWidth > 0, viewportHeight > 0 else { return nil }

        let heightRatio = viewportHeight / height
        let widthRatio = viewportWidth / width
        let scaleRatio: Double

        switch contentMode {
        case .scaleAspectFit:
            scaleRatio = min(heightRatio, widthRatio)
        case .scaleAspectFill:
            scaleRatio = max(heightRatio, widthRatio)
        case .scaleToFill:
            scaleRatio = 0
        @unknown default:
            scaleRatio = 0
        }

        guard scaleRatio > 0 else { return nil }

        let scaleY = Float(height * scaleRatio / viewportHeight)
        let scaleX = Float(width * scaleRatio / viewportWidth)
        let shouldUpdateToDefault = (heightRatio != 1 || widthRatio != 1) && shouldUpdateToDefaultWhenOutputSizeChanged
        return (scaleX, scaleY, shouldUpdateToDefault)
    }
}
