import CoreGraphics
import Foundation

final class IRGLRenderSession: @unchecked Sendable {
    struct Selection {
        let didSelect: Bool
        let aspect: CGFloat
    }

    struct Diagnostics {
        let isClosed: Bool
        let pixelFormat: IRPixelFormat
        let renderModeCount: Int
        let hasCurrentMode: Bool
        let viewportRange: CGRect
        let prepareCount: Int
        let resizeCount: Int
        let modeSelectionCount: Int
        let rejectedOperationCount: Int
        let executor: IRGLRenderExecutor.Diagnostics
        let surface: IRGLMetalSurfaceSession.Diagnostics
        let frames: IRGLFrameSubmissionSession.Diagnostics
    }

    let executor: IRGLRenderExecutor
    let surface: IRGLMetalSurfaceSession
    let frames: IRGLFrameSubmissionSession

    private var pixelFormat: IRPixelFormat = .YUV_IRPixelFormat
    private var modes: [IRGLRenderMode] = []
    private var currentMode: IRGLRenderMode?
    private var viewportRange: CGRect = .zero
    private var contentMode: IRGLRenderContentMode = .scaleAspectFit
    private var closed = false
    private var prepareCount = 0
    private var resizeCount = 0
    private var modeSelectionCount = 0
    private var rejectedOperationCount = 0

    init(
        executor: IRGLRenderExecutor = IRGLRenderExecutor(),
        surfaceDependencies: IRGLMetalSurfaceDependencies = .system,
        frameRenderOperation:
            IRGLFrameSubmissionSession.RenderOperation? = nil
    ) {
        self.executor = executor
        surface = IRGLMetalSurfaceSession(
            executor: executor,
            dependencies: surfaceDependencies
        )
        frames = IRGLFrameSubmissionSession(
            executor: executor,
            renderOperation: frameRenderOperation
        )
    }

    var diagnostics: Diagnostics {
        executor.sync {
            Diagnostics(
                isClosed: closed,
                pixelFormat: pixelFormat,
                renderModeCount: modes.count,
                hasCurrentMode: currentMode != nil,
                viewportRange: viewportRange,
                prepareCount: prepareCount,
                resizeCount: resizeCount,
                modeSelectionCount: modeSelectionCount,
                rejectedOperationCount: rejectedOperationCount,
                executor: executor.diagnostics,
                surface: surface.diagnostics,
                frames: frames.diagnostics
            )
        }
    }

    var isCurrentExecutor: Bool {
        executor.isCurrentExecutor
    }

    var registeredModes: [IRGLRenderMode] {
        executor.sync { modes }
    }

    var selectedMode: IRGLRenderMode? {
        executor.sync { currentMode }
    }

    var currentViewportRange: CGRect {
        executor.sync { viewportRange }
    }

    var currentPixelFormat: IRPixelFormat {
        executor.sync { pixelFormat }
    }

    var lastFrameSize: (width: Int, height: Int) {
        let diagnostics = frames.diagnostics
        return (
            diagnostics.lastFrameWidth,
            diagnostics.lastFrameHeight
        )
    }

    func setRenderCompletionHandler(_ handler: (() -> Void)?) {
        frames.setCompletionHandler(handler)
    }

    @discardableResult
    func prepare(
        surfaceInput: IRGLMetalSurfaceSession.Input,
        pixelFormat: IRPixelFormat,
        replacingModes: [IRGLRenderMode]? = nil
    ) -> Bool {
        executor.sync {
            guard !closed else {
                rejectedOperationCount += 1
                return false
            }
            prepareCount += 1

            let pixelFormatChanged = self.pixelFormat != pixelFormat
            self.pixelFormat = pixelFormat
            if let replacingModes {
                modes = replacingModes
            }
            if modes.isEmpty {
                modes = IRGLRenderModeFactory.createNormalModes(with: nil)
            }

            frames.reset()
            let surfaceReady = surface.prepare(surfaceInput)
            for mode in modes {
                mode.renderer = nil
                if pixelFormatChanged {
                    mode.program = nil
                    mode.shiftController.program = nil
                }
            }
            updateViewportFromSurfaceLocked(resetTransform: false)
            currentMode = modes.first
            if let currentMode {
                _ = configureModeLocked(currentMode)
            }
            return surfaceReady
        }
    }

    @discardableResult
    func resize(
        surfaceInput: IRGLMetalSurfaceSession.Input,
        resetTransform: Bool = false
    ) -> Bool {
        executor.sync {
            guard !closed else {
                rejectedOperationCount += 1
                return false
            }
            guard surface.resize(surfaceInput) else { return false }
            resizeCount += 1
            updateViewportFromSurfaceLocked(
                resetTransform: resetTransform
            )
            _ = frames.submit(nil, context: renderContextLocked())
            return true
        }
    }

    @discardableResult
    func select(
        _ renderMode: IRGLRenderMode?,
        renderImmediately: Bool
    ) -> Selection {
        executor.sync {
            guard !closed,
                  let renderMode,
                  modes.contains(where: { $0 === renderMode }) else {
                rejectedOperationCount += 1
                return Selection(
                    didSelect: false,
                    aspect: CGFloat(currentMode?.aspect ?? 0)
                )
            }

            modeSelectionCount += 1
            currentMode = renderMode
            let aspect = configureModeLocked(renderMode)
            if renderImmediately {
                _ = frames.submit(nil, context: renderContextLocked())
            }
            return Selection(didSelect: true, aspect: aspect)
        }
    }

    func setCompatibilityMode(_ renderMode: IRGLRenderMode?) {
        executor.sync {
            guard !closed else { return }
            currentMode = renderMode
        }
    }

    func setContentMode(_ contentMode: IRGLRenderContentMode) {
        executor.sync {
            guard !closed else { return }
            self.contentMode = contentMode
            currentMode?.program?.contentMode = contentMode
        }
    }

    @discardableResult
    func submit(_ frame: IRFFVideoFrame?) -> Bool {
        executor.sync {
            guard !closed else {
                rejectedOperationCount += 1
                return false
            }
            return frames.submit(frame, context: renderContextLocked())
        }
    }

    @discardableResult
    func clear() -> Bool {
        executor.sync {
            guard !closed else {
                rejectedOperationCount += 1
                return false
            }
            return frames.clear(context: renderContextLocked())
        }
    }

    func resetViewport(
        width: Float,
        height: Float,
        resetTransform: Bool
    ) {
        executor.sync {
            guard !closed,
                  width.isFinite,
                  height.isFinite,
                  width >= 0,
                  height >= 0 else {
                rejectedOperationCount += 1
                return
            }
            let proposed = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(width),
                height: CGFloat(height)
            )
            guard let viewportSize = IRGLProgram2D.viewportSize(
                from: proposed
            ) else {
                rejectedOperationCount += 1
                return
            }
            applyViewportLocked(
                width: viewportSize.width,
                height: viewportSize.height,
                resetTransform: resetTransform
            )
            _ = frames.submit(nil, context: renderContextLocked())
        }
    }

    func updateScope(
        fx: Float,
        fy: Float,
        scaleX: Float,
        scaleY: Float
    ) {
        executor.sync {
            guard !closed else { return }
            if let program = currentMode?.program {
                if let pano = program as? IRGLProgram2DFisheye2Pano,
                   let controller = pano.tramsformController {
                    let scope = controller.getScope()
                    controller.update(
                        fx: Float(scope.w) / 2,
                        fy: Float(scope.h) / 2,
                        sx: scope.scaleX * scaleX,
                        sy: scope.scaleY * scaleY
                    )
                } else {
                    program.didPinchByfx(
                        fx,
                        fy: fy,
                        dsx: scaleX,
                        dsy: scaleY
                    )
                }
            } else {
                frames.updateFallbackFisheye(
                    fx: fx,
                    fy: fy,
                    sx: scaleX,
                    sy: scaleY
                )
            }
            _ = frames.submit(nil, context: renderContextLocked())
        }
    }

    func scroll(dx: Float, dy: Float) {
        executor.sync {
            guard !closed else { return }
            if let program = currentMode?.program {
                program.didPanBydx(dx, dy: dy)
                updatePanoOffsetLocked(
                    program: program,
                    dx: dx
                )
            } else {
                frames.scrollFallbackFisheye(dx: dx, dy: dy)
            }
            _ = frames.submit(nil, context: renderContextLocked())
        }
    }

    func scroll(degreeX: Float, degreeY: Float) {
        executor.sync {
            guard !closed else { return }
            if let program = currentMode?.program {
                program.didPanByDegreeX(
                    degreeX,
                    degreeY: degreeY
                )
            } else {
                frames.scrollFallbackFisheye(
                    degreeX: degreeX,
                    degreeY: degreeY
                )
            }
            _ = frames.submit(nil, context: renderContextLocked())
        }
    }

    func reset() {
        executor.sync {
            guard !closed else { return }
            frames.reset()
            surface.reset()
            modes.forEach { $0.renderer = nil }
            viewportRange = .zero
        }
    }

    @discardableResult
    func close() -> Bool {
        executor.sync {
            guard !closed else { return false }
            closed = true
            _ = frames.close()
            _ = surface.close()
            modes.forEach { $0.renderer = nil }
            modes = []
            currentMode = nil
            viewportRange = .zero
            return true
        }
    }

    func runSync(_ operation: @escaping () -> Void) {
        executor.sync(operation)
    }

    private func configureModeLocked(
        _ renderMode: IRGLRenderMode
    ) -> CGFloat {
        if renderMode.program == nil {
            renderMode.buildIRGLProgram(
                pixelFormat: pixelFormat,
                viewprotRange: viewportRange,
                parameter: renderMode.parameter
            )
        } else {
            renderMode.program?.setViewportRange(
                viewportRange,
                resetTransform: false
            )
        }
        if renderMode.renderer == nil,
           let renderer = surface.resourceSnapshot?.renderer {
            renderMode.renderer = IRGLRenderStrategyFactory.make(
                for: renderMode,
                renderer: renderer
            )
        }
        frames.configureMode(
            renderMode,
            viewportSize: viewportRange.size
        )
        return CGFloat(renderMode.aspect)
    }

    private func updateViewportFromSurfaceLocked(
        resetTransform: Bool
    ) {
        let surfaceState = surface.diagnostics
        applyViewportLocked(
            width: surfaceState.pixelWidth,
            height: surfaceState.pixelHeight,
            resetTransform: resetTransform
        )
    }

    private func applyViewportLocked(
        width: Int,
        height: Int,
        resetTransform: Bool
    ) {
        viewportRange = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
        currentMode?.program?.setViewportRange(
            viewportRange,
            resetTransform: resetTransform
        )
        frames.resetFisheyeViewport(
            width: width,
            height: height,
            resetTransform: resetTransform
        )
    }

    private func renderContextLocked()
        -> IRGLFrameSubmissionSession.RenderContext
    {
        IRGLFrameSubmissionSession.RenderContext(
            surface: surface.resourceSnapshot,
            mode: currentMode,
            contentMode: contentMode
        )
    }

    private func updatePanoOffsetLocked(
        program: IRGLProgram2D,
        dx: Float
    ) {
        guard let pano = program as? IRGLProgram2DFisheye2Pano,
              let params = pano.metalFish2PanoParams,
              let controller = pano.tramsformController else {
            return
        }
        let scope = controller.getScope()
        guard scope.w > 0,
              scope.scaleX.isFinite,
              scope.scaleX > 0,
              dx.isFinite,
              params.outputWidth > 0,
              params.offsetX.isFinite else {
            return
        }

        let outputWidth = Float(params.outputWidth)
        let widthScale = outputWidth / Float(scope.w)
        let delta = dx / scope.scaleX * widthScale
        guard outputWidth.isFinite,
              widthScale.isFinite,
              widthScale > 0,
              delta.isFinite,
              let offsetX =
                IRGLProgram2DFisheye2Pano.normalizedOffsetX(
                    currentOffset: params.offsetX,
                    delta: delta,
                    outputWidth: params.outputWidth
                ) else {
            return
        }
        params.offsetX = offsetX
    }
}
