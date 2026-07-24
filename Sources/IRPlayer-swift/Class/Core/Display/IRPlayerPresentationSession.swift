import Foundation
import UIKit

enum IRMainThreadExecutor {
    static func sync<Result>(_ body: () -> Result) -> Result {
        if Thread.isMainThread {
            return body()
        }
        return DispatchQueue.main.sync(execute: body)
    }

    static func execute(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }
}

protocol IRPlayerMotionControlling: AnyObject {
    var targetView: IRGLView? { get set }
    var smoothScroll: IRSmoothScrollController? { get set }

    @discardableResult
    func resetUnit() -> Bool
    func stopMotionDetection()
}

extension IRSensor: IRPlayerMotionControlling {}

struct IRPlayerPresentationDependencies {
    let displayFactory: (any IRGLViewHost) -> IRGLView
    let gestureFactory: () -> IRGLGestureController
    let scrollFactory: (IRGLView) -> IRSmoothScrollController
    let motionFactory: () -> any IRPlayerMotionControlling

    static var system: IRPlayerPresentationDependencies {
        IRPlayerPresentationDependencies(
            displayFactory: { IRGLView(frame: .zero, player: $0) },
            gestureFactory: { IRGLGestureController() },
            scrollFactory: { IRSmoothScrollController(targetView: $0) },
            motionFactory: { IRSensor() }
        )
    }
}

final class IRPlayerPresentationSession:
    NSObject,
    IRGLViewHost,
    IRGLViewDelegate,
    @unchecked Sendable
{
    struct Diagnostics {
        let isClosed: Bool
        let hasDisplayView: Bool
        let hasGestureController: Bool
        let hasScrollController: Bool
        let hasMotionController: Bool
        let currentMode: IRGLRenderMode?
        let renderModeCount: Int
        let gravityMode: IRGravityMode
    }

    private let stateLock = NSLock()
    private let dependencies: IRPlayerPresentationDependencies

    private var storedGravityMode: IRGravityMode
    private var storedDisplayView: IRGLView?
    private var gestureController: IRGLGestureController?
    private var scrollController: IRSmoothScrollController?
    private var motionController: (any IRPlayerMotionControlling)?
    private var tapHandler: ((IRPLFView) -> Void)?
    private var closed = false

    init(
        gravityMode: IRGravityMode = .resizeAspect,
        videoType: IRVideoType = .normal,
        displayMode: IRDisplayMode = .normal,
        dependencies: IRPlayerPresentationDependencies = .system
    ) {
        storedGravityMode = gravityMode
        self.dependencies = dependencies
        super.init()
        IRMainThreadExecutor.sync {
            setup(videoType: videoType, displayMode: displayMode)
        }
    }

    deinit {
        close()
    }

    var diagnostics: Diagnostics {
        let state: (
            Bool,
            IRGLView?,
            IRGLGestureController?,
            IRSmoothScrollController?,
            (any IRPlayerMotionControlling)?,
            IRGravityMode
        )
        stateLock.lock()
        state = (
            closed,
            storedDisplayView,
            gestureController,
            scrollController,
            motionController,
            storedGravityMode
        )
        stateLock.unlock()

        let modeState = IRMainThreadExecutor.sync {
            (
                state.1?.getCurrentRenderMode(),
                state.1?.getRenderModes().count ?? 0
            )
        }
        return Diagnostics(
            isClosed: state.0,
            hasDisplayView: state.1 != nil,
            hasGestureController: state.2 != nil,
            hasScrollController: state.3 != nil,
            hasMotionController: state.4 != nil,
            currentMode: modeState.0,
            renderModeCount: modeState.1,
            gravityMode: state.5
        )
    }

    var viewGravityMode: IRGravityMode {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedGravityMode
    }

    var displayView: IRGLView? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedDisplayView
    }

    var renderModes: [IRGLRenderMode] {
        guard let displayView else { return [] }
        return IRMainThreadExecutor.sync {
            displayView.getRenderModes()
        }
    }

    var currentRenderMode: IRGLRenderMode? {
        guard let displayView else { return nil }
        return IRMainThreadExecutor.sync {
            displayView.getCurrentRenderMode()
        }
    }

    func setTapHandler(_ handler: ((IRPLFView) -> Void)?) {
        stateLock.lock()
        tapHandler = handler
        stateLock.unlock()
    }

    func setGravityMode(_ gravityMode: IRGravityMode) {
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return
        }
        storedGravityMode = gravityMode
        let displayView = storedDisplayView
        stateLock.unlock()
        IRMainThreadExecutor.sync {
            displayView?.reloadGravityMode()
        }
    }

    func setRenderModes(_ modes: [IRGLRenderMode]) {
        guard let displayView else { return }
        IRMainThreadExecutor.sync {
            displayView.setRenderModes(modes)
            synchronizeModeReferences(with: displayView)
        }
    }

    @discardableResult
    func selectRenderMode(_ renderMode: IRGLRenderMode) -> Bool {
        guard let displayView else { return false }
        return IRMainThreadExecutor.sync {
            guard displayView.choose(
                renderMode: renderMode,
                withImmediatelyRenderOnce: true
            ) else {
                return false
            }
            synchronizeModeReferences(with: displayView)
            return true
        }
    }

    func apply(videoType: IRVideoType, displayMode: IRDisplayMode) {
        guard let displayView else { return }
        IRMainThreadExecutor.sync {
            let configuration = IRPlayerRenderConfiguration.make(
                videoType: videoType,
                displayMode: displayMode
            )
            if let modes = configuration.modes {
                displayView.setRenderModes(modes)
            }
            if let gravityMode = configuration.gravityMode {
                stateLock.lock()
                storedGravityMode = gravityMode
                stateLock.unlock()
                displayView.reloadGravityMode()
            }

            switch configuration.interaction {
            case .gestures:
                installGestures(on: displayView)
            case .motion:
                installMotion(on: displayView)
            }
            synchronizeModeReferences(with: displayView)
        }
    }

    func attachPlayerView(_ playerView: IRPLFView) {
        guard let displayView else { return }
        IRMainThreadExecutor.sync {
            cleanPlayerSubviews(of: displayView)
            displayView.addSubview(playerView)
            playerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(
                    equalTo: displayView.topAnchor
                ),
                playerView.bottomAnchor.constraint(
                    equalTo: displayView.bottomAnchor
                ),
                playerView.leftAnchor.constraint(
                    equalTo: displayView.leftAnchor
                ),
                playerView.rightAnchor.constraint(
                    equalTo: displayView.rightAnchor
                )
            ])
        }
    }

    func cleanPlayerView() {
        guard let displayView else { return }
        IRMainThreadExecutor.sync {
            cleanPlayerSubviews(of: displayView)
        }
    }

    func updateFrame(_ frame: CGRect) {
        guard let displayView else { return }
        IRMainThreadExecutor.sync {
            displayView.update(frame: frame)
        }
    }

    func snapshot() -> IRPLFImage? {
        guard let displayView else { return nil }
        return IRMainThreadExecutor.sync {
            displayView.createImageFromFramebuffer()
        }
    }

    func clearEmptyBuffer() {
        guard let displayView else { return }
        IRMainThreadExecutor.sync {
            displayView.cleanEmptyBuffer()
        }
    }

    func handleSingleTap() {
        stateLock.lock()
        let delivery = closed
            ? nil
            : tapHandler.flatMap { handler in
                storedDisplayView.map { (handler, $0 as IRPLFView) }
            }
        stateLock.unlock()
        if let (handler, view) = delivery {
            handler(view)
        }
    }

    @discardableResult
    func close() -> Bool {
        let resources: (
            IRGLView?,
            IRGLGestureController?,
            IRSmoothScrollController?,
            (any IRPlayerMotionControlling)?
        )
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return false
        }
        closed = true
        resources = (
            storedDisplayView,
            gestureController,
            scrollController,
            motionController
        )
        storedDisplayView = nil
        gestureController = nil
        scrollController = nil
        motionController = nil
        tapHandler = nil
        stateLock.unlock()

        IRMainThreadExecutor.sync {
            resources.3?.stopMotionDetection()
            if let displayView = resources.0 {
                resources.1?.removeGesture(to: displayView)
                cleanPlayerSubviews(of: displayView)
                displayView.close()
            }
            resources.1?.singleTapped = nil
            resources.1?.delegate = nil
            resources.1?.smoothScroll = nil
            _ = resources.2?.close()
        }
        return true
    }

    func glViewWillBeginZooming(_ glView: IRGLView?) {
        currentMotionController?.stopMotionDetection()
    }

    func glViewDidEndZooming(
        _ glView: IRGLView?,
        atScale scale: CGFloat
    ) {
        _ = currentMotionController?.resetUnit()
    }

    func glViewWillBeginDragging(_ glView: IRGLView?) {
        currentMotionController?.stopMotionDetection()
    }

    func glViewDidEndDragging(
        _ glView: IRGLView?,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate {
            _ = currentMotionController?.resetUnit()
        }
    }

    func glViewDidEndDecelerating(_ glView: IRGLView?) {
        _ = currentMotionController?.resetUnit()
    }

    func glViewDidScroll(toBounds glView: IRGLView?) {}

    private var currentMotionController:
        (any IRPlayerMotionControlling)?
    {
        stateLock.lock()
        defer { stateLock.unlock() }
        return motionController
    }

    private func setup(
        videoType: IRVideoType,
        displayMode: IRDisplayMode
    ) {
        let displayView = dependencies.displayFactory(self)
        let scrollController = dependencies.scrollFactory(displayView)
        let gestureController = dependencies.gestureFactory()

        scrollController.currentMode = displayView.getCurrentRenderMode()
        scrollController.delegate = self
        gestureController.currentMode = displayView.getCurrentRenderMode()
        gestureController.smoothScroll = scrollController
        gestureController.delegate = self
        gestureController.singleTapped = { [weak self] _ in
            self?.handleSingleTap()
        }

        stateLock.lock()
        storedDisplayView = displayView
        self.scrollController = scrollController
        self.gestureController = gestureController
        stateLock.unlock()
        apply(videoType: videoType, displayMode: displayMode)
    }

    private func installGestures(on displayView: IRGLView) {
        let resources = interactionResources
        resources.motion?.stopMotionDetection()
        resources.gesture?.removeGesture(to: displayView)
        resources.gesture?.addGesture(to: displayView)
        stateLock.lock()
        motionController = nil
        stateLock.unlock()
    }

    private func installMotion(on displayView: IRGLView) {
        let resources = interactionResources
        resources.gesture?.removeGesture(to: displayView)
        resources.motion?.stopMotionDetection()

        let motion = dependencies.motionFactory()
        motion.targetView = displayView
        motion.smoothScroll = resources.gesture?.smoothScroll
        stateLock.lock()
        motionController = motion
        stateLock.unlock()
        _ = motion.resetUnit()
    }

    private var interactionResources: (
        gesture: IRGLGestureController?,
        motion: (any IRPlayerMotionControlling)?
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (gestureController, motionController)
    }

    private func synchronizeModeReferences(with displayView: IRGLView) {
        let currentMode = displayView.getCurrentRenderMode()
        stateLock.lock()
        let gestureController = gestureController
        let scrollController = scrollController
        stateLock.unlock()
        gestureController?.currentMode = currentMode
        scrollController?.currentMode = currentMode
    }

    private func cleanPlayerSubviews(of displayView: IRGLView) {
        displayView.subviews.forEach { $0.removeFromSuperview() }
    }
}
