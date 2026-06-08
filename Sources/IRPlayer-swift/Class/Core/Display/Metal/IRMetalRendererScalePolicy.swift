//
//  IRMetalRendererScalePolicy.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/6/2.
//

import CoreGraphics

enum IRMetalRendererScalePolicy {
    static func computeScale(contentMode: IRGLRenderContentMode, frameSize: CGSize, drawableSize: CGSize) -> CGSize {
        guard frameSize.width.isFinite,
              frameSize.height.isFinite,
              drawableSize.width.isFinite,
              drawableSize.height.isFinite,
              frameSize.width > 0,
              frameSize.height > 0,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let sx = drawableSize.width / frameSize.width
        let sy = drawableSize.height / frameSize.height

        switch contentMode {
        case .scaleAspectFit:
            let s = min(sx, sy)
            return CGSize(width: s / sx, height: s / sy)
        case .scaleAspectFill:
            let s = max(sx, sy)
            return CGSize(width: s / sx, height: s / sy)
        case .scaleToFill:
            return CGSize(width: 1, height: 1)
        @unknown default:
            return CGSize(width: 1, height: 1)
        }
    }
}
