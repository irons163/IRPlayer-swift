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
        let renderDidComplete: IRGLRenderCompletion
    }

    struct RenderResult {
        enum CompletionMode {
            case immediate
            case deferred
        }

        let currentImage: CIImage?
        let didSubmitRender: Bool
        let completionMode: CompletionMode

        init(
            currentImage: CIImage?,
            didCompleteRender: Bool
        ) {
            self.currentImage = currentImage
            didSubmitRender = didCompleteRender
            completionMode = .immediate
        }

        init(
            currentImage: CIImage?,
            didSubmitRender: Bool,
            completionMode: CompletionMode
        ) {
            self.currentImage = currentImage
            self.didSubmitRender = didSubmitRender
            self.completionMode = completionMode
        }
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
        let inFlightRenderCount: Int
        let presentationLeaseCount: Int
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

    private enum PresentationReleaseAction: Equatable {
        case stop
        case cancel
    }

    private struct PresentationLease {
        let frame: IRFFAVYUVVideoFrame
        var inFlightRenderCount: Int
        var releaseAction: PresentationReleaseAction?
    }

    private var currentFrame: IRFFVideoFrame?
    private var currentImage: CIImage?
    private var lastRenderContext: RenderContext?
    private var currentPresentationID: ObjectIdentifier?
    private var presentationLeases:
        [ObjectIdentifier: PresentationLease] = [:]
    private var nextRenderSubmissionID: UInt64 = 0
    private var activeRenderSubmissions: Set<UInt64> = []
    private var presentationIDBySubmission:
        [UInt64: ObjectIdentifier] = [:]
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
        self.renderState.setFish2PanoPixelMapReadyHandler {
            [weak self] in
            self?.scheduleFish2PanoRedraw()
        }
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
                lastFrameHeight: lastFrameHeight,
                inFlightRenderCount:
                    activeRenderSubmissions.count,
                presentationLeaseCount:
                    presentationLeases.count
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
            lastRenderContext = context

            if let frame {
                submissionCount += 1
                let dimensions = frame.dimensionSnapshot()
                lastFrameWidth = dimensions.width
                lastFrameHeight = dimensions.height
                replaceCurrentFrame(with: frame)
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
            lastRenderContext = context
            clearCount += 1
            retireAllPresentationLeases(
                action: .cancel
            )
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
            retireAllPresentationLeases(
                action: .cancel
            )
            currentFrame = nil
            currentImage = nil
            lastRenderContext = nil
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
            retireAllPresentationLeases(
                action: .cancel
            )
            currentFrame = nil
            currentImage = nil
            lastRenderContext = nil
            completionHandler = nil
            renderState.setFish2PanoPixelMapReadyHandler(nil)
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
            renderState.configureVR(renderMode: mode)
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
        let renderSubmissionID =
            allocateRenderSubmissionID()
        let submittedFrame = currentFrame
        let result = renderOperation(
            RenderInput(
                currentFrame: currentFrame,
                currentImage: currentImage,
                context: context,
                renderState: renderState,
                colorSpace: colorSpace,
                renderDidComplete: { [self] in
                    executor.async { [self] in
                        completeRenderSubmission(
                            renderSubmissionID
                        )
                    }
                }
            )
        )
        currentImage = result.currentImage
        guard result.didSubmitRender else {
            incompleteRenderCount += 1
            return false
        }

        activeRenderSubmissions.insert(
            renderSubmissionID
        )
        if let presentationID =
                presentationID(for: submittedFrame),
           var lease =
                presentationLeases[presentationID] {
            lease.inFlightRenderCount += 1
            presentationLeases[presentationID] = lease
            presentationIDBySubmission[
                renderSubmissionID
            ] = presentationID
        }
        if result.completionMode == .immediate {
            completeRenderSubmission(
                renderSubmissionID
            )
        }
        return true
    }

    private func scheduleFish2PanoRedraw() {
        executor.async { [weak self] in
            guard let self,
                  !self.closed,
                  self.currentFrame != nil,
                  let context = self.lastRenderContext,
                  context.mode is IRGLRenderMode2DFisheye2Pano else {
                return
            }
            self.redrawCount += 1
            _ = self.renderCurrent(context: context)
        }
    }

    private func replaceCurrentFrame(
        with frame: IRFFVideoFrame
    ) {
        if currentFrame === frame {
            return
        }
        retireCurrentPresentationLease(
            action: .stop
        )
        currentFrame = frame
        guard let softwareFrame =
                frame as? IRFFAVYUVVideoFrame else {
            currentPresentationID = nil
            return
        }

        let presentationID =
            ObjectIdentifier(softwareFrame)
        if var existingLease =
                presentationLeases[presentationID] {
            existingLease.releaseAction = nil
            presentationLeases[presentationID] =
                existingLease
        } else {
            presentationLeases[presentationID] =
                PresentationLease(
                    frame: softwareFrame,
                    inFlightRenderCount: 0,
                    releaseAction: nil
                )
        }
        currentPresentationID = presentationID
        if !softwareFrame.playing {
            softwareFrame.startPlaying()
        }
    }

    private func presentationID(
        for frame: IRFFVideoFrame?
    ) -> ObjectIdentifier? {
        guard let softwareFrame =
                frame as? IRFFAVYUVVideoFrame else {
            return nil
        }
        return ObjectIdentifier(softwareFrame)
    }

    private func retireCurrentPresentationLease(
        action: PresentationReleaseAction
    ) {
        guard let currentPresentationID else {
            return
        }
        self.currentPresentationID = nil
        retirePresentationLease(
            currentPresentationID,
            action: action
        )
    }

    private func retireAllPresentationLeases(
        action: PresentationReleaseAction
    ) {
        currentPresentationID = nil
        for presentationID
            in Array(presentationLeases.keys) {
            retirePresentationLease(
                presentationID,
                action: action
            )
        }
    }

    private func retirePresentationLease(
        _ presentationID: ObjectIdentifier,
        action: PresentationReleaseAction
    ) {
        guard var lease =
                presentationLeases[presentationID] else {
            return
        }
        if action == .cancel
            || lease.releaseAction == nil {
            lease.releaseAction = action
        }
        presentationLeases[presentationID] = lease
        releasePresentationLeaseIfPossible(
            presentationID
        )
    }

    private func releasePresentationLeaseIfPossible(
        _ presentationID: ObjectIdentifier
    ) {
        guard let lease =
                presentationLeases[presentationID],
              lease.inFlightRenderCount == 0,
              let releaseAction =
                lease.releaseAction else {
            return
        }
        presentationLeases.removeValue(
            forKey: presentationID
        )
        switch releaseAction {
        case .stop:
            lease.frame.stopPlaying()
        case .cancel:
            lease.frame.cancel()
        }
    }

    private func allocateRenderSubmissionID() -> UInt64 {
        repeat {
            nextRenderSubmissionID &+= 1
        } while activeRenderSubmissions.contains(
            nextRenderSubmissionID
        )
        return nextRenderSubmissionID
    }

    private func completeRenderSubmission(
        _ renderSubmissionID: UInt64
    ) {
        guard activeRenderSubmissions.remove(
            renderSubmissionID
        ) != nil else {
            return
        }

        if let presentationID =
                presentationIDBySubmission.removeValue(
                    forKey: renderSubmissionID
                ),
           var lease =
                presentationLeases[presentationID] {
            lease.inFlightRenderCount =
                max(lease.inFlightRenderCount - 1, 0)
            presentationLeases[presentationID] = lease
            releasePresentationLeaseIfPossible(
                presentationID
            )
        }

        completedRenderCount += 1
        completionHandler?()
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
                renderDidComplete:
                    input.renderDidComplete,
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
            didSubmitRender: result.didSubmitRender,
            completionMode: .deferred
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
