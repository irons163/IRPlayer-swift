//
//  IRMetalRenderer+Render2D.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/3/13.
//

import Foundation
import Metal
import CoreVideo
import simd
import QuartzCore

extension IRMetalRenderer {

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        let scale = computeScale(contentMode: contentMode, frameSize: CGSize(width: frame.width, height: frame.height), drawableSize: drawableSize)
        var scaleVector = SIMD2<Float>(Float(scale.width), Float(scale.height)) * zoomScale

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var translationVector = translation
        encoder.setVertexBytes(&translationVector, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
        encoder.setViewport(MTLViewport(originX: 0,
                                        originY: Double(drawableSize.height),
                                        width: Double(drawableSize.width),
                                        height: -Double(drawableSize.height),
                                        znear: 0,
                                        zfar: 1))

        if let pixelRenderer = pixelRenderer(for: frame) {
            if pixelRenderer.render2D(renderer: self, frame: frame, encoder: encoder) {
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return true
            }
        }

        encoder.endEncoding()
        return false
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool {
        guard !viewports.isEmpty, viewports.count == contentModes.count else { return false }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return false }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return false }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var didRender = false
        for (index, viewport) in viewports.enumerated() {
            guard viewport.width > 0, viewport.height > 0 else { continue }
            let originY = drawableSize.height - viewport.origin.y
            encoder.setViewport(MTLViewport(originX: Double(viewport.origin.x),
                                            originY: Double(originY),
                                            width: Double(viewport.size.width),
                                            height: -Double(viewport.size.height),
                                            znear: 0,
                                            zfar: 1))

            let targetSize = viewport.size
            let scale = computeScale(contentMode: contentModes[index],
                                     frameSize: CGSize(width: frame.width, height: frame.height),
                                     drawableSize: targetSize)
            let zoomScale = index < zoomScales.count ? zoomScales[index] : 1
            var scaleVector = SIMD2<Float>(Float(scale.width), Float(scale.height)) * zoomScale
            encoder.setVertexBytes(&scaleVector, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            var translationVector = index < translations.count ? translations[index] : SIMD2<Float>(repeating: 0)
            encoder.setVertexBytes(&translationVector, length: MemoryLayout<SIMD2<Float>>.size, index: 2)

            if let pixelRenderer = pixelRenderer(for: frame) {
                didRender = pixelRenderer.render2D(renderer: self, frame: frame, encoder: encoder) || didRender
            }
        }

        encoder.endEncoding()
        if didRender {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        return didRender
    }

    func renderClear(to drawable: CAMetalDrawable) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let renderPass = currentRenderPassDescriptor(drawable: drawable) else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

}
