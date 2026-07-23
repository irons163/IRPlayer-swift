import AVFoundation
import QuartzCore
import UIKit

enum IRDisplayRendererType: UInt {
    case empty
    case AVPlayerLayer
    case AVPlayerPixelBufferVR
    case FFmpegPixelBuffer
    case FFmpegPixelBufferVR
}

protocol IRGLViewHost: AnyObject {
    var viewGravityMode: IRGravityMode { get }
}

struct IRGLViewRuntimeDependencies {
    let renderSession: IRGLRenderSession
    let snapshotSession: IRGLSnapshotSession
    let avPlayerLayerSession: IRGLAVPlayerLayerSession

    static var system: IRGLViewRuntimeDependencies {
        IRGLViewRuntimeDependencies(
            renderSession: IRGLRenderSession(),
            snapshotSession: IRGLSnapshotSession(),
            avPlayerLayerSession: IRGLAVPlayerLayerSession()
        )
    }
}

private final class IRGLViewPresentationState {
    private let lock = NSLock()
    private var storedRendererType: IRDisplayRendererType = .empty
    private var storedAspect: CGFloat = 0

    var rendererType: IRDisplayRendererType {
        lock.lock()
        defer { lock.unlock() }
        return storedRendererType
    }

    var aspect: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return storedAspect
    }

    @discardableResult
    func setRendererType(_ value: IRDisplayRendererType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedRendererType != value else { return false }
        storedRendererType = value
        return true
    }

    @discardableResult
    func setAspect(_ value: CGFloat) -> Bool {
        let normalized = value.isFinite && value > 0 ? value : 0
        lock.lock()
        defer { lock.unlock() }
        guard storedAspect != normalized else { return false }
        storedAspect = normalized
        return true
    }
}

public class IRGLView: UIView, IRFFDecoderVideoOutput {
    typealias FittedImageTransform =
        IRGLFrameSubmissionSession.FittedImageTransform

    weak var abstractPlayer: (any IRGLViewHost)?

    private let renderSession: IRGLRenderSession
    private let snapshotSession: IRGLSnapshotSession
    private let avPlayerLayerSession: IRGLAVPlayerLayerSession
    private let presentationState = IRGLViewPresentationState()

    var irPixelFormat: IRPixelFormat {
        get { renderSession.currentPixelFormat }
        set { initGL(with: newValue) }
    }

    var lastFrameWidth: Int {
        renderSession.lastFrameSize.width
    }

    var lastFrameHeight: Int {
        renderSession.lastFrameSize.height
    }

    var willDoSnapshot: Bool {
        get { snapshotSession.hasPendingRequest }
        set {
            if newValue {
                _ = snapshotSession.request()
            } else {
                _ = snapshotSession.cancelPendingRequest()
            }
        }
    }

    var mode: IRGLRenderMode? {
        get { renderSession.selectedMode }
        set { renderSession.setCompatibilityMode(newValue) }
    }

    var modes: [IRGLRenderMode] {
        get { renderSession.registeredModes }
        set { setRenderModes(newValue) }
    }

    var viewprotRange: CGRect {
        renderSession.currentViewportRange
    }

    var aspect: CGFloat {
        get { presentationState.aspect }
        set {
            guard presentationState.setAspect(newValue) else { return }
            performUIKitMutation { [weak self] in
                self?.reloadViewFrameOnMain()
            }
        }
    }

    var rendererType: IRDisplayRendererType {
        get { presentationState.rendererType }
        set {
            guard presentationState.setRendererType(newValue) else {
                return
            }
            performUIKitMutation { [weak self] in
                self?.reloadViewOnMain()
            }
        }
    }

    var renderDiagnostics: IRGLRenderSession.Diagnostics {
        renderSession.diagnostics
    }

    var snapshotDiagnostics: IRGLSnapshotSession.Diagnostics {
        snapshotSession.diagnostics
    }

    var avPlayerLayerDiagnostics:
        IRGLAVPlayerLayerSession.Diagnostics
    {
        avPlayerLayerSession.diagnostics
    }

    required init?(coder: NSCoder) {
        let dependencies = IRGLViewRuntimeDependencies.system
        renderSession = dependencies.renderSession
        snapshotSession = dependencies.snapshotSession
        avPlayerLayerSession = dependencies.avPlayerLayerSession
        super.init(coder: coder)
        finishInitialization()
    }

    override init(frame: CGRect) {
        let dependencies = IRGLViewRuntimeDependencies.system
        renderSession = dependencies.renderSession
        snapshotSession = dependencies.snapshotSession
        avPlayerLayerSession = dependencies.avPlayerLayerSession
        super.init(frame: frame)
        finishInitialization()
    }

    init(frame: CGRect, player: any IRGLViewHost) {
        let dependencies = IRGLViewRuntimeDependencies.system
        renderSession = dependencies.renderSession
        snapshotSession = dependencies.snapshotSession
        avPlayerLayerSession = dependencies.avPlayerLayerSession
        abstractPlayer = player
        super.init(frame: frame)
        finishInitialization()
    }

    init(
        frame: CGRect,
        player: (any IRGLViewHost)? = nil,
        runtimeDependencies: IRGLViewRuntimeDependencies
    ) {
        renderSession = runtimeDependencies.renderSession
        snapshotSession = runtimeDependencies.snapshotSession
        avPlayerLayerSession =
            runtimeDependencies.avPlayerLayerSession
        abstractPlayer = player
        super.init(frame: frame)
        finishInitialization()
    }

    deinit {
        close()
    }

    static public override var layerClass: AnyClass {
        CAMetalLayer.self
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        avPlayerLayerSession.layout(bounds: bounds)
        updateViewPort(1)
    }

    public override var contentMode: UIView.ContentMode {
        didSet {}
    }

    func initDefaultValue() {}

    func initGL(with pixelFormat: IRPixelFormat) {
        guard let input = captureSurfaceInput(viewportScale: 1) else {
            return
        }
        IRMainThreadExecutor.sync {
            CATransaction.flush()
        }
        _ = renderSession.prepare(
            surfaceInput: input,
            pixelFormat: pixelFormat
        )
        synchronizeAspectWithSelectedMode()
    }

    func close() {
        _ = snapshotSession.close()
        let layerSession = avPlayerLayerSession
        if renderSession.isCurrentExecutor, !Thread.isMainThread {
            DispatchQueue.main.async {
                _ = layerSession.close()
            }
        } else {
            _ = layerSession.close()
        }
        _ = renderSession.close()
    }

    func reset() {
        renderSession.reset()
    }

    func updateViewPort(_ viewportScale: Float) {
        guard viewportScale.isFinite,
              viewportScale > 0,
              let input = captureSurfaceInput(
                  viewportScale: CGFloat(viewportScale)
              ) else {
            return
        }
        _ = renderSession.resize(surfaceInput: input)
    }

    static func drawablePixelSize(
        from size: CGSize
    ) -> (width: Int, height: Int)? {
        IRGLMetalSurfaceSession.pixelSize(from: size)
    }

    func changeGLRenderContentMode() {
        performUIKitMutation { [weak self] in
            guard let self else { return }
            let contentMode: IRGLRenderContentMode
            switch abstractPlayer?.viewGravityMode {
            case .resizeAspect:
                contentMode = .scaleAspectFit
            case .resizeAspectFill:
                contentMode = .scaleAspectFill
            case .resize:
                contentMode = .scaleToFill
            case nil:
                contentMode = .scaleAspectFit
            }
            renderSession.setContentMode(contentMode)
        }
    }

    func resetAllViewport(
        w: Float,
        h: Float,
        resetTransform: Bool
    ) {
        renderSession.resetViewport(
            width: w,
            height: h,
            resetTransform: resetTransform
        )
    }

    func updateScope(
        byFx fx: Float,
        fy: Float,
        dsx: Float,
        dsy: Float
    ) {
        renderSession.updateScope(
            fx: fx,
            fy: fy,
            scaleX: dsx,
            scaleY: dsy
        )
    }

    func scroll(byDx dx: Float, dy: Float) {
        renderSession.scroll(dx: dx, dy: dy)
    }

    func scroll(byDegreeX degreeX: Float, degreeY: Float) {
        renderSession.scroll(
            degreeX: degreeX,
            degreeY: degreeY
        )
    }

    func render(_ frame: IRFFVideoFrame?) {
        _ = renderSession.submit(frame)
    }

    static func translationVector(
        for program: IRGLProgram2D?
    ) -> SIMD2<Float> {
        IRGLFrameSubmissionSession.translationVector(
            for: program?.tramsformController?.getScope()
        )
    }

    static func fittedImageTransform(
        imageExtent: CGRect,
        targetRect: CGRect,
        contentMode: IRGLRenderContentMode
    ) -> FittedImageTransform? {
        IRGLFrameSubmissionSession.fittedImageTransform(
            imageExtent: imageExtent,
            targetRect: targetRect,
            contentMode: contentMode
        )
    }

    func setRenderModes(_ modes: [IRGLRenderMode]) {
        guard let input = captureSurfaceInput(viewportScale: 1) else {
            return
        }
        _ = renderSession.prepare(
            surfaceInput: input,
            pixelFormat: irPixelFormat,
            replacingModes: modes
        )
        synchronizeAspectWithSelectedMode()
    }

    func initModes() {
        guard getRenderModes().isEmpty else { return }
        setRenderModes(
            IRGLRenderModeFactory.createNormalModes(with: nil)
        )
    }

    func setupModes() {
        initModes()
        contentMode = .scaleAspectFit
        _ = choose(
            renderMode: getRenderModes().first,
            withImmediatelyRenderOnce: false
        )
    }

    func getRenderModes() -> [IRGLRenderMode] {
        renderSession.registeredModes
    }

    func getCurrentRenderMode() -> IRGLRenderMode? {
        renderSession.selectedMode
    }

    func choose(
        renderMode: IRGLRenderMode?,
        withImmediatelyRenderOnce immediatelyRenderOnce: Bool
    ) -> Bool {
        let selection = renderSession.select(
            renderMode,
            renderImmediately: immediatelyRenderOnce
        )
        if selection.didSelect {
            aspect = selection.aspect
        }
        return selection.didSelect
    }

    func runSyncInQueue(_ block: @escaping () -> Void) {
        renderSession.runSync(block)
    }

    func clearCanvas() {
        _ = renderSession.clear()
    }

    func doSnapShot() {
        _ = snapshotSession.request()
    }

    func saveSnapShot() {
        snapshotSession.renderDidComplete { [weak self] in
            self?.captureFramebufferOnMain()
        }
    }

    func saveSnapshotAlbum(_ snapshot: UIImage) {
        IRPhotoSaver.save(snapshot, toAlbum: "Snapshots")
    }

    func createImageFromFramebuffer() -> UIImage {
        if renderSession.isCurrentExecutor, !Thread.isMainThread {
            return UIImage()
        }
        return IRMainThreadExecutor.sync {
            captureFramebufferOnMain()
        }
    }

    func cleanEmptyBuffer() {
        _ = renderSession.clear()
    }

    var attachedAVPlayer: AVPlayer? {
        avPlayerLayerSession.attachedPlayer
    }

    func setAVPlayer(_ player: AVPlayer?) {
        performUIKitMutation { [weak self] in
            guard let self else { return }
            _ = self.avPlayerLayerSession.setPlayer(
                player,
                hostLayer: self.layer,
                bounds: self.bounds,
                gravity: self.avPlayerLayerGravity
            )
        }
    }

    func reloadView() {
        performUIKitMutation { [weak self] in
            self?.reloadViewOnMain()
        }
    }

    func reloadGravityMode() {
        changeGLRenderContentMode()
        performUIKitMutation { [weak self] in
            guard let self else { return }
            avPlayerLayerSession.updateGravity(
                avPlayerLayerGravity
            )
        }
    }

    func updateDisplayViewLayout(_ frame: CGRect) {
        performUIKitMutation { [weak self] in
            guard let self else { return }
            reloadViewFrameOnMain()
            updateViewPort(1)
        }
    }

    func reloadViewFrame() {
        performUIKitMutation { [weak self] in
            self?.reloadViewFrameOnMain()
        }
    }

    func update(frame: CGRect) {
        performUIKitMutation { [weak self] in
            guard let self else { return }
            self.frame = frame
            reloadViewOnMain()
        }
    }

    func cleanView() {
        cleanViewCleanAVPlayerLayer(
            true,
            cleanAVPlayerView: true,
            cleanFFPlayerView: true
        )
    }

    func cleanViewIgnore() {
        switch rendererType {
        case .empty:
            cleanView()
        case .AVPlayerLayer:
            cleanViewCleanAVPlayerLayer(
                false,
                cleanAVPlayerView: true,
                cleanFFPlayerView: true
            )
        case .AVPlayerPixelBufferVR:
            cleanViewCleanAVPlayerLayer(
                true,
                cleanAVPlayerView: false,
                cleanFFPlayerView: true
            )
        case .FFmpegPixelBuffer, .FFmpegPixelBufferVR:
            cleanViewCleanAVPlayerLayer(
                true,
                cleanAVPlayerView: true,
                cleanFFPlayerView: false
            )
        }
    }

    func cleanViewCleanAVPlayerLayer(
        _ cleanAVPlayerLayer: Bool,
        cleanAVPlayerView: Bool,
        cleanFFPlayerView: Bool
    ) {
        if cleanAVPlayerLayer {
            let layerSession = avPlayerLayerSession
            performUIKitMutation {
                layerSession.reset()
            }
        }
        cleanEmptyBuffer()
    }

    static func texUVTextureLayout(
        width: Int,
        height: Int
    ) -> (bytesPerRow: Int, totalByteCount: Int)? {
        IRGLViewRenderState.texUVTextureLayout(
            width: width,
            height: height
        )
    }

    public func send(videoFrame: IRFFVideoFrame) {
        render(videoFrame)
    }

    private func finishInitialization() {
        renderSession.setRenderCompletionHandler { [weak self] in
            self?.snapshotSession.renderDidComplete { [weak self] in
                self?.captureFramebufferOnMain()
            }
        }
        initGL(with: .YUV_IRPixelFormat)
    }

    private func synchronizeAspectWithSelectedMode() {
        aspect = CGFloat(
            renderSession.selectedMode?.aspect ?? 0
        )
    }

    private func captureSurfaceInput(
        viewportScale: CGFloat
    ) -> IRGLMetalSurfaceSession.Input? {
        guard !renderSession.isCurrentExecutor else { return nil }
        return IRMainThreadExecutor.sync {
            guard let metalLayer = layer as? CAMetalLayer else {
                return nil
            }
            return IRGLMetalSurfaceSession.Input(
                layer: metalLayer,
                bounds: bounds,
                screenScale: UIScreen.main.scale,
                viewportScale: viewportScale
            )
        }
    }

    private func captureFramebufferOnMain() -> UIImage {
        let size = layer.bounds.size
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return UIImage()
        }
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        drawHierarchy(
            in: layer.bounds,
            afterScreenUpdates: false
        )
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    private func reloadViewOnMain() {
        cleanViewIgnore()
        if rendererType == .AVPlayerLayer {
            avPlayerLayerSession.layout(bounds: bounds)
        }
        reloadViewFrameOnMain()
        updateViewPort(1)
    }

    private func reloadViewFrameOnMain() {
        guard let superviewBounds = superview?.bounds else { return }
        let aspect = presentationState.aspect
        guard aspect > 0,
              superviewBounds.width.isFinite,
              superviewBounds.height.isFinite,
              superviewBounds.width >= 0,
              superviewBounds.height > 0 else {
            frame = superviewBounds
            return
        }

        let superviewAspect =
            superviewBounds.width / superviewBounds.height
        if superviewAspect < aspect {
            let height = superviewBounds.width / aspect
            frame = CGRect(
                x: 0,
                y: (superviewBounds.height - height) / 2,
                width: superviewBounds.width,
                height: height
            )
        } else if superviewAspect > aspect {
            let width = superviewBounds.height * aspect
            frame = CGRect(
                x: (superviewBounds.width - width) / 2,
                y: 0,
                width: width,
                height: superviewBounds.height
            )
        } else {
            frame = superviewBounds
        }
    }

    private var avPlayerLayerGravity: AVLayerVideoGravity {
        switch abstractPlayer?.viewGravityMode {
        case .resize:
            return .resize
        case .resizeAspectFill:
            return .resizeAspectFill
        case .resizeAspect, nil:
            return .resizeAspect
        }
    }

    private func performUIKitMutation(
        _ mutation: @escaping () -> Void
    ) {
        if Thread.isMainThread {
            mutation()
        } else if renderSession.isCurrentExecutor {
            DispatchQueue.main.async(execute: mutation)
        } else {
            DispatchQueue.main.sync(execute: mutation)
        }
    }
}
