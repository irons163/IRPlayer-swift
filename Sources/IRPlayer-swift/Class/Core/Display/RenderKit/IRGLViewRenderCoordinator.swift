//
//  IRGLViewRenderCoordinator.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import CoreGraphics
import CoreImage
import Metal
import QuartzCore
import UIKit

final class IRGLViewRenderCoordinator {
    struct Context {
        let metalLayer: CAMetalLayer
        let currentFrame: IRFFVideoFrame?
        let currentImage: CIImage?
        let mode: IRGLRenderMode?
        let fallbackRenderer: IRGLRenderInternal?
        let renderContentMode: IRGLRenderContentMode
        let device: MTLDevice?
        let commandQueue: MTLCommandQueue?
        let ciContext: CIContext?
        let colorSpace: CGColorSpace
        let renderState: IRGLViewRenderState
        let renderDidComplete: IRGLRenderCompletion
        let makeImage: (IRFFVideoFrame) -> CIImage?
        let fitImage: (CIImage, CGRect) -> CIImage
    }

    struct Result {
        let currentImage: CIImage?
        let didSubmitRender: Bool
    }

    func render(context: Context) -> Result {
        let metalLayer = context.metalLayer
        let drawableSize = metalLayer.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else {
            return Result(currentImage: context.currentImage, didSubmitRender: false)
        }

        if let frame = context.currentFrame,
           let renderer = (context.mode?.renderer as? IRGLRenderInternal) ?? context.fallbackRenderer,
           let drawable = metalLayer.nextDrawable() {
            context.mode?.program?.setRenderFrame(frame)
            if let result = context.renderState.renderMulti4PIfNeeded(frame: frame,
                                                                      mode: context.mode,
                                                                      renderer: renderer,
                                                                      drawable: drawable,
                                                                      drawableSize: drawableSize,
                                                                      device: context.device,
                                                                      completion: context.renderDidComplete) {
                return Result(
                    currentImage: context.currentImage,
                    didSubmitRender: result
                )
            }
            if let result = context.renderState.renderFish2PanoIfNeeded(frame: frame,
                                                                       mode: context.mode,
                                                                       renderer: renderer,
                                                                       drawable: drawable,
                                                                       drawableSize: drawableSize,
                                                                       renderContentMode: context.renderContentMode,
                                                                       device: context.device,
                                                                       completion: context.renderDidComplete) {
                return Result(
                    currentImage: context.currentImage,
                    didSubmitRender: result
                )
            }
            if let result = context.renderState.renderDistortionIfNeeded(frame: frame,
                                                                        mode: context.mode,
                                                                        renderer: renderer,
                                                                        drawable: drawable,
                                                                        drawableSize: drawableSize,
                                                                        renderContentMode: context.renderContentMode,
                                                                        device: context.device,
                                                                        completion: context.renderDidComplete) {
                return Result(
                    currentImage: context.currentImage,
                    didSubmitRender: result
                )
            }
            if let result = context.renderState.renderFisheyeIfNeeded(frame: frame,
                                                                     mode: context.mode,
                                                                     renderer: renderer,
                                                                     drawable: drawable,
                                                                     drawableSize: drawableSize,
                                                                     device: context.device,
                                                                     completion: context.renderDidComplete) {
                return Result(
                    currentImage: context.currentImage,
                    didSubmitRender: result
                )
            }
            if let result = context.renderState.renderVRIfNeeded(frame: frame,
                                                                mode: context.mode,
                                                                renderer: renderer,
                                                                drawable: drawable,
                                                                drawableSize: drawableSize,
                                                                device: context.device,
                                                                completion: context.renderDidComplete) {
                return Result(
                    currentImage: context.currentImage,
                    didSubmitRender: result
                )
            }

            let zoomScale = Float((context.mode?.program?.getCurrentScale().x) ?? 1)
            let translation =
                IRGLFrameSubmissionSession.translationVector(
                    for: (context.mode?.program as? IRGLProgram2D)?
                        .tramsformController?.getScope()
                )
            if renderer.render(frame: frame,
                               to: drawable,
                               contentMode: context.renderContentMode,
                               drawableSize: drawableSize,
                               zoomScale: zoomScale,
                               translation: translation,
                               completion: context.renderDidComplete) {
                return Result(currentImage: context.currentImage, didSubmitRender: true)
            }
            if frame is IRFFCVYUVVideoFrame || frame is IRFFAVYUVVideoFrame {
                return Result(currentImage: context.currentImage, didSubmitRender: false)
            }
        }

        var image = context.currentImage
        if image == nil, let frame = context.currentFrame {
            image = context.makeImage(frame)
        }
        guard let currentImage = image else {
            return Result(currentImage: image, didSubmitRender: false)
        }
        guard let drawable = metalLayer.nextDrawable() else {
            return Result(currentImage: image, didSubmitRender: false)
        }
        guard let commandQueue = context.commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let ciContext = context.ciContext else {
            return Result(currentImage: image, didSubmitRender: false)
        }

        let targetRect = CGRect(origin: .zero, size: metalLayer.drawableSize)
        guard targetRect.width > 0, targetRect.height > 0 else {
            return Result(currentImage: image, didSubmitRender: false)
        }
        let fittedImage = context.fitImage(currentImage, targetRect)

        ciContext.render(fittedImage,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: targetRect,
                         colorSpace: context.colorSpace)
        commandBuffer.addCompletedHandler { _ in
            context.renderDidComplete()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return Result(currentImage: image, didSubmitRender: true)
    }
}
