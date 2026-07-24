import Foundation

struct IRFFPlayerPresentation: Equatable {
    let pixelFormat: IRPixelFormat
    let rendererType: IRDisplayRendererType

    static func configuration(
        hardwareDecoderEnabled: Bool,
        videoType: IRVideoType
    ) -> IRFFPlayerPresentation {
        let pixelFormat: IRPixelFormat = hardwareDecoderEnabled
            ? .NV12_IRPixelFormat
            : .YUV_IRPixelFormat
        let rendererType: IRDisplayRendererType = videoType == .vr
            ? .FFmpegPixelBufferVR
            : .FFmpegPixelBuffer
        return IRFFPlayerPresentation(
            pixelFormat: pixelFormat,
            rendererType: rendererType
        )
    }

    func apply(to displayView: IRGLView) {
        IRMainThreadExecutor.sync {
            displayView.irPixelFormat = pixelFormat
            displayView.rendererType = rendererType
        }
    }

    static func clear(_ displayView: IRGLView?) {
        guard let displayView else { return }
        IRMainThreadExecutor.sync {
            displayView.cleanEmptyBuffer()
        }
    }
}
