import UIKit

public extension IRPlayerImp {
    func setupPlayerView(_ playerView: IRPLFView) {
        presentationSession.attachPlayerView(playerView)
    }

    func selectRenderMode(renderMode: IRGLRenderMode) {
        _ = presentationSession.selectRenderMode(renderMode)
    }

    func updateGraphicsViewFrame(frame: CGRect) {
        presentationSession.updateFrame(frame)
    }

    func snapshot() -> UIImage? {
        presentationSession.snapshot()
    }

    func glViewWillBeginZooming(_ glView: IRGLView?) {
        presentationSession.glViewWillBeginZooming(glView)
    }

    func glViewDidEndZooming(
        _ glView: IRGLView?,
        atScale scale: CGFloat
    ) {
        presentationSession.glViewDidEndZooming(glView, atScale: scale)
    }

    func glViewWillBeginDragging(_ glView: IRGLView?) {
        presentationSession.glViewWillBeginDragging(glView)
    }

    func glViewDidEndDragging(
        _ glView: IRGLView?,
        willDecelerate decelerate: Bool
    ) {
        presentationSession.glViewDidEndDragging(
            glView,
            willDecelerate: decelerate
        )
    }

    func glViewDidEndDecelerating(_ glView: IRGLView?) {
        presentationSession.glViewDidEndDecelerating(glView)
    }

    func glViewDidScroll(toBounds glView: IRGLView?) {
        presentationSession.glViewDidScroll(toBounds: glView)
    }
}

extension IRPlayerImp {
    func cleanPlayerView() {
        presentationSession.cleanPlayerView()
    }
}
