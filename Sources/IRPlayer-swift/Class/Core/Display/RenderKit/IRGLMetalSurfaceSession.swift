import CoreGraphics
import CoreImage
import Metal
import QuartzCore

enum IRGLMetalSurfaceFailure: Equatable {
    case missingDevice
    case missingCommandQueue
    case missingCIContext
    case renderer(IRMetalRendererBuildFailure)
}

enum IRGLMetalSurfacePhase: Equatable {
    case idle
    case ready
    case unavailable(IRGLMetalSurfaceFailure)
    case closed
}

struct IRGLMetalSurfaceDependencies {
    let makeDevice: () -> MTLDevice?
    let makeCommandQueue: (MTLDevice) -> MTLCommandQueue?
    let makeCIContext: (MTLDevice) -> CIContext?
    let makeRenderer:
        (MTLDevice, MTLCommandQueue)
        -> Result<IRMetalRenderer, IRMetalRendererBuildFailure>

    static var system: IRGLMetalSurfaceDependencies {
        IRGLMetalSurfaceDependencies(
            makeDevice: { MTLCreateSystemDefaultDevice() },
            makeCommandQueue: { $0.makeCommandQueue() },
            makeCIContext: { CIContext(mtlDevice: $0) },
            makeRenderer: {
                device,
                commandQueue in
                IRMetalRenderer.make(
                    device: device,
                    commandQueue: commandQueue
                )
            }
        )
    }
}

final class IRGLMetalSurfaceSession: @unchecked Sendable {
    struct Input {
        let layer: CAMetalLayer
        let bounds: CGRect
        let screenScale: CGFloat
        let viewportScale: CGFloat

        init(
            layer: CAMetalLayer,
            bounds: CGRect,
            screenScale: CGFloat,
            viewportScale: CGFloat = 1
        ) {
            self.layer = layer
            self.bounds = bounds
            self.screenScale = screenScale
            self.viewportScale = viewportScale
        }
    }

    struct Resources {
        let layer: CAMetalLayer
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        let ciContext: CIContext
        let renderer: IRMetalRenderer
    }

    struct Diagnostics: Equatable {
        let phase: IRGLMetalSurfacePhase
        let generation: UInt64
        let prepareCount: Int
        let resizeCount: Int
        let rejectedOperationCount: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let hasCompleteResources: Bool
    }

    private let executor: IRGLRenderExecutor
    private let dependencies: IRGLMetalSurfaceDependencies

    private var phase: IRGLMetalSurfacePhase = .idle
    private var resources: Resources?
    private var generation: UInt64 = 0
    private var prepareCount = 0
    private var resizeCount = 0
    private var rejectedOperationCount = 0
    private var pixelWidth = 0
    private var pixelHeight = 0

    init(
        executor: IRGLRenderExecutor,
        dependencies: IRGLMetalSurfaceDependencies = .system
    ) {
        self.executor = executor
        self.dependencies = dependencies
    }

    var diagnostics: Diagnostics {
        executor.sync {
            Diagnostics(
                phase: phase,
                generation: generation,
                prepareCount: prepareCount,
                resizeCount: resizeCount,
                rejectedOperationCount: rejectedOperationCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                hasCompleteResources: resources != nil
            )
        }
    }

    var resourceSnapshot: Resources? {
        executor.sync { resources }
    }

    @discardableResult
    func prepare(_ input: Input) -> Bool {
        executor.sync {
            guard phase != .closed else {
                rejectedOperationCount += 1
                return false
            }

            prepareCount += 1
            releaseGeneration(clearLayer: true)
            input.layer.device = nil
            configureLayer(input.layer, screenScale: input.screenScale)

            guard let device = dependencies.makeDevice() else {
                phase = .unavailable(.missingDevice)
                return false
            }
            guard let commandQueue = dependencies.makeCommandQueue(device) else {
                phase = .unavailable(.missingCommandQueue)
                return false
            }
            guard let ciContext = dependencies.makeCIContext(device) else {
                phase = .unavailable(.missingCIContext)
                return false
            }
            let renderer: IRMetalRenderer
            switch dependencies.makeRenderer(
                device,
                commandQueue
            ) {
            case let .success(readyRenderer):
                renderer = readyRenderer
            case let .failure(failure):
                phase = .unavailable(.renderer(failure))
                return false
            }

            input.layer.device = device
            resources = Resources(
                layer: input.layer,
                device: device,
                commandQueue: commandQueue,
                ciContext: ciContext,
                renderer: renderer
            )
            generation &+= 1
            phase = .ready
            _ = resizeLocked(input)
            return true
        }
    }

    @discardableResult
    func resize(_ input: Input) -> Bool {
        executor.sync {
            guard phase == .ready,
                  let resources,
                  resources.layer === input.layer else {
                rejectedOperationCount += 1
                return false
            }
            return resizeLocked(input)
        }
    }

    func reset() {
        executor.sync {
            guard phase != .closed else { return }
            releaseGeneration(clearLayer: true)
            phase = .idle
        }
    }

    @discardableResult
    func close() -> Bool {
        executor.sync {
            guard phase != .closed else { return false }
            releaseGeneration(clearLayer: true)
            phase = .closed
            return true
        }
    }

    static func pixelSize(
        bounds: CGRect,
        screenScale: CGFloat,
        viewportScale: CGFloat
    ) -> (width: Int, height: Int)? {
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              screenScale.isFinite,
              viewportScale.isFinite,
              bounds.width > 0,
              bounds.height > 0,
              screenScale > 0,
              viewportScale > 0 else {
            return nil
        }

        let width = bounds.width * screenScale * viewportScale
        let height = bounds.height * screenScale * viewportScale
        guard width.isFinite,
              height.isFinite,
              width > 0,
              height > 0,
              width <= CGFloat(Int.max),
              height <= CGFloat(Int.max) else {
            return nil
        }
        return (Int(width), Int(height))
    }

    static func pixelSize(
        from drawableSize: CGSize
    ) -> (width: Int, height: Int)? {
        pixelSize(
            bounds: CGRect(origin: .zero, size: drawableSize),
            screenScale: 1,
            viewportScale: 1
        )
    }

    private func resizeLocked(_ input: Input) -> Bool {
        guard let size = Self.pixelSize(
            bounds: input.bounds,
            screenScale: input.screenScale,
            viewportScale: input.viewportScale
        ) else {
            rejectedOperationCount += 1
            return false
        }

        let drawableSize = CGSize(
            width: input.bounds.width * input.screenScale * input.viewportScale,
            height: input.bounds.height * input.screenScale * input.viewportScale
        )
        input.layer.contentsScale = input.screenScale
        input.layer.drawableSize = drawableSize
        pixelWidth = size.width
        pixelHeight = size.height
        resizeCount += 1
        return true
    }

    private func configureLayer(
        _ layer: CAMetalLayer,
        screenScale: CGFloat
    ) {
        if screenScale.isFinite, screenScale > 0 {
            layer.contentsScale = screenScale
        }
        layer.isOpaque = true
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
    }

    private func releaseGeneration(clearLayer: Bool) {
        if clearLayer {
            resources?.layer.device = nil
        }
        resources = nil
        pixelWidth = 0
        pixelHeight = 0
    }
}
