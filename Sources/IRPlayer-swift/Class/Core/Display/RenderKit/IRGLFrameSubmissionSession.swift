import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import UIKit

final class IRGLFrameSubmissionSession: @unchecked Sendable {
    struct RenderContext {
        let surface: IRGLMetalSurfaceSession.Resources?
        let mode: IRGLRenderMode?
        let contentMode: IRGLRenderContentMode
    }

    struct RenderInput {
        let currentFrame: IRFFVideoFrame?
        let currentImage: CIImage?
        let context: RenderContext
        let renderState: IRGLViewRenderState
        let colorSpace: CGColorSpace
    }

    struct RenderResult {
        let currentImage: CIImage?
        let didCompleteRender: Bool
    }

    struct Diagnostics: Equatable {
        let isClosed: Bool
        let submissionCount: Int
        let redrawCount: Int
        let clearCount: Int
        let resetCount: Int
        let completedRenderCount: Int
        let incompleteRenderCount: Int
        let rejectedSubmissionCount: Int
        let hasCurrentFrame: Bool
        let hasCurrentImage: Bool
        let lastFrameWidth: Int
        let lastFrameHeight: Int
    }

    struct FittedImageTransform: Equatable {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let translationX: CGFloat
        let translationY: CGFloat
    }

    typealias RenderOperation = (RenderInput) -> RenderResult

    private let executor: IRGLRenderExecutor
    private let renderOperation: RenderOperation
    private let renderState: IRGLViewRenderState
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private var currentFrame: IRFFVideoFrame?
    private var currentImage: CIImage?
    private var completionHandler: (() -> Void)?
    private var closed = false
    private var submissionCount = 0
    private var redrawCount = 0
    private var clearCount = 0
    private var resetCount = 0
    private var completedRenderCount = 0
    private var incompleteRenderCount = 0
    private var rejectedSubmissionCount = 0
    private var lastFrameWidth = 0
    private var lastFrameHeight = 0

    init(
        executor: IRGLRenderExecutor,
        renderState: IRGLViewRenderState = IRGLViewRenderState(),
        renderOperation: RenderOperation? = nil
    ) {
        self.executor = executor
        self.renderState = renderState
        self.renderOperation = renderOperation ?? Self.systemRender
    }

    var diagnostics: Diagnostics {
        executor.sync {
            Diagnostics(
                isClosed: closed,
                submissionCount: submissionCount,
                redrawCount: redrawCount,
                clearCount: clearCount,
                resetCount: resetCount,
                completedRenderCount: completedRenderCount,
                incompleteRenderCount: incompleteRenderCount,
                rejectedSubmissionCount: rejectedSubmissionCount,
                hasCurrentFrame: currentFrame != nil,
                hasCurrentImage: currentImage != nil,
                lastFrameWidth: lastFrameWidth,
                lastFrameHeight: lastFrameHeight
            )
        }
    }

    func setCompletionHandler(_ handler: (() -> Void)?) {
        executor.sync {
            completionHandler = handler
        }
    }

    @discardableResult
    func submit(
        _ frame: IRFFVideoFrame?,
        context: RenderContext
    ) -> Bool {
        executor.sync {
            guard !closed else {
                rejectedSubmissionCount += 1
                return false
            }

            if let frame {
                submissionCount += 1
                lastFrameWidth = Int(frame.width)
                lastFrameHeight = Int(frame.height)
                currentFrame = frame
                currentImage = nil
            } else {
                redrawCount += 1
            }
            return renderCurrent(context: context)
        }
    }

    @discardableResult
    func clear(context: RenderContext) -> Bool {
        executor.sync {
            guard !closed else {
                rejectedSubmissionCount += 1
                return false
            }
            clearCount += 1
            currentFrame = nil

            let drawableSize = context.surface?.layer.drawableSize ?? .zero
            if drawableSize.width > 0,
               drawableSize.height > 0,
               drawableSize.width.isFinite,
               drawableSize.height.isFinite {
                currentImage = CIImage(color: .black).cropped(
                    to: CGRect(origin: .zero, size: drawableSize)
                )
            } else {
                currentImage = nil
            }
            return renderCurrent(context: context)
        }
    }

    func reset() {
        executor.sync {
            guard !closed else { return }
            resetCount += 1
            currentFrame = nil
            currentImage = nil
            lastFrameWidth = 0
            lastFrameHeight = 0
            renderState.reset()
        }
    }

    @discardableResult
    func close() -> Bool {
        executor.sync {
            guard !closed else { return false }
            closed = true
            currentFrame = nil
            currentImage = nil
            completionHandler = nil
            renderState.reset()
            return true
        }
    }

    func configureMode(
        _ mode: IRGLRenderMode,
        viewportSize: CGSize
    ) {
        executor.sync {
            guard !closed else { return }
            renderState.configureFisheye(
                renderMode: mode,
                viewportSize: viewportSize
            )
            renderState.configureFish2Pano(renderMode: mode)
        }
    }

    func resetFisheyeViewport(
        width: Int,
        height: Int,
        resetTransform: Bool
    ) {
        executor.sync {
            guard !closed else { return }
            renderState.resetFisheyeViewport(
                width: width,
                height: height,
                resetTransform: resetTransform
            )
        }
    }

    func updateFallbackFisheye(
        fx: Float,
        fy: Float,
        sx: Float,
        sy: Float
    ) {
        executor.sync {
            guard !closed else { return }
            renderState.updateFallbackFisheye(
                fx: fx,
                fy: fy,
                sx: sx,
                sy: sy
            )
        }
    }

    func scrollFallbackFisheye(dx: Float, dy: Float) {
        executor.sync {
            guard !closed else { return }
            renderState.scrollFallbackFisheye(dx: dx, dy: dy)
        }
    }

    func scrollFallbackFisheye(
        degreeX: Float,
        degreeY: Float
    ) {
        executor.sync {
            guard !closed else { return }
            renderState.scrollFallbackFisheye(
                degreeX: degreeX,
                degreeY: degreeY
            )
        }
    }

    static func fittedImageTransform(
        imageExtent: CGRect,
        targetRect: CGRect,
        contentMode: IRGLRenderContentMode
    ) -> FittedImageTransform? {
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

        let scaledExtent = imageExtent.applying(
            CGAffineTransform(scaleX: scaleX, y: scaleY)
        )
        return FittedImageTransform(
            scaleX: scaleX,
            scaleY: scaleY,
            translationX:
                (targetRect.width - scaledExtent.width) / 2
                - scaledExtent.origin.x,
            translationY:
                (targetRect.height - scaledExtent.height) / 2
                - scaledExtent.origin.y
        )
    }

    static func translationVector(
        for scope: IRGLScope2D?
    ) -> SIMD2<Float> {
        guard let scope,
              scope.w > 0,
              scope.h > 0,
              scope.scaleX.isFinite,
              scope.scaleY.isFinite,
              scope.offsetX.isFinite,
              scope.offsetY.isFinite,
              scope.scaleX > 0,
              scope.scaleY > 0 else {
            return SIMD2<Float>(repeating: 0)
        }

        let x: Float = scope.scaleX >= 1
            ? (scope.offsetX * scope.scaleX * 2 / Float(scope.w))
                + 1 - scope.scaleX
            : 0
        let y: Float = scope.scaleY >= 1
            ? -((scope.offsetY * scope.scaleY * 2 / Float(scope.h))
                + 1 - scope.scaleY)
            : 0
        return SIMD2<Float>(x, y)
    }

    private func renderCurrent(context: RenderContext) -> Bool {
        let result = renderOperation(
            RenderInput(
                currentFrame: currentFrame,
                currentImage: currentImage,
                context: context,
                renderState: renderState,
                colorSpace: colorSpace
            )
        )
        currentImage = result.currentImage
        if result.didCompleteRender {
            completedRenderCount += 1
            completionHandler?()
        } else {
            incompleteRenderCount += 1
        }
        return result.didCompleteRender
    }

    private static func systemRender(_ input: RenderInput) -> RenderResult {
        guard let surface = input.context.surface else {
            return RenderResult(
                currentImage: input.currentImage,
                didCompleteRender: false
            )
        }

        let coordinator = IRGLViewRenderCoordinator()
        let result = coordinator.render(
            context: IRGLViewRenderCoordinator.Context(
                metalLayer: surface.layer,
                currentFrame: input.currentFrame,
                currentImage: input.currentImage,
                mode: input.context.mode,
                fallbackRenderer: surface.renderer,
                renderContentMode: input.context.contentMode,
                device: surface.device,
                commandQueue: surface.commandQueue,
                ciContext: surface.ciContext,
                colorSpace: input.colorSpace,
                renderState: input.renderState,
                makeImage: makeImage,
                fitImage: { image, rect in
                    fitImage(
                        image,
                        in: rect,
                        contentMode: input.context.contentMode
                    )
                }
            )
        )
        return RenderResult(
            currentImage: result.currentImage,
            didCompleteRender: result.didCompleteRender
        )
    }

    private static func fitImage(
        _ image: CIImage,
        in rect: CGRect,
        contentMode: IRGLRenderContentMode
    ) -> CIImage {
        guard let transform = fittedImageTransform(
            imageExtent: image.extent,
            targetRect: rect,
            contentMode: contentMode
        ) else {
            return image
        }
        return image
            .transformed(
                by: CGAffineTransform(
                    scaleX: transform.scaleX,
                    y: transform.scaleY
                )
            )
            .transformed(
                by: CGAffineTransform(
                    translationX: transform.translationX,
                    y: transform.translationY
                )
            )
    }

    private static func makeImage(
        from frame: IRFFVideoFrame
    ) -> CIImage? {
        if let cvFrame = frame as? IRFFCVYUVVideoFrame {
            return CIImage(cvPixelBuffer: cvFrame.pixelBuffer)
        }
        if let yuvFrame = frame as? IRFFAVYUVVideoFrame,
           let image = yuvFrame.image() {
            return CIImage(image: image)
        }
        if let rgbFrame = frame as? IRVideoFrameRGB,
           let image = rgbFrame.asImage() {
            return CIImage(image: image)
        }
        return nil
    }
}
