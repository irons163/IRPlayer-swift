//
//  IRGLViewPolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import UIKit

enum IRGLViewPolicy {
    static func drawablePixelSize(from size: CGSize) -> (width: Int, height: Int)? {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width <= CGFloat(Int.max),
              size.height <= CGFloat(Int.max) else {
            return nil
        }
        return (Int(size.width), Int(size.height))
    }

    static func fittedImageTransform(imageExtent: CGRect,
                                     targetRect: CGRect,
                                     contentMode: IRGLRenderContentMode) -> IRGLView.FittedImageTransform? {
        guard imageExtent.origin.x.isFinite,
              imageExtent.origin.y.isFinite,
              imageExtent.width.isFinite,
              imageExtent.height.isFinite,
              targetRect.width.isFinite,
              targetRect.height.isFinite,
              imageExtent.width > 0,
              imageExtent.height > 0,
              targetRect.width > 0,
              targetRect.height > 0 else {
            return nil
        }

        var scaleX = targetRect.width / imageExtent.width
        var scaleY = targetRect.height / imageExtent.height

        switch contentMode {
        case .scaleAspectFit:
            let scale = min(scaleX, scaleY)
            scaleX = scale
            scaleY = scale
        case .scaleAspectFill:
            let scale = max(scaleX, scaleY)
            scaleX = scale
            scaleY = scale
        case .scaleToFill:
            break
        @unknown default:
            break
        }

        let scaledExtent = imageExtent.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
        let translationX = (targetRect.width - scaledExtent.width) / 2.0 - scaledExtent.origin.x
        let translationY = (targetRect.height - scaledExtent.height) / 2.0 - scaledExtent.origin.y
        return IRGLView.FittedImageTransform(scaleX: scaleX,
                                             scaleY: scaleY,
                                             translationX: translationX,
                                             translationY: translationY)
    }

    static func texUVTextureLayout(width: Int, height: Int) -> (bytesPerRow: Int, totalByteCount: Int)? {
        guard width > 0, height > 0 else { return nil }

        let bytesPerTexel = MemoryLayout<Float>.size * 2
        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerTexel)
        guard !rowOverflow, bytesPerRow > 0 else { return nil }

        let (totalByteCount, totalOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !totalOverflow, totalByteCount > 0 else { return nil }

        return (bytesPerRow: bytesPerRow, totalByteCount: totalByteCount)
    }
}
