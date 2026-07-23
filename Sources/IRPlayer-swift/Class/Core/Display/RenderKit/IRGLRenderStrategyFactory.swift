import Metal
import QuartzCore
import simd

private class IRGLRenderStrategyBase: IRGLRenderInternal {
    private let renderer: IRMetalRenderer

    init(renderer: IRMetalRenderer) {
        self.renderer = renderer
    }

    func render(
        frame: IRFFVideoFrame,
        to drawable: CAMetalDrawable,
        contentMode: IRGLRenderContentMode,
        drawableSize: CGSize,
        zoomScale: Float,
        translation: SIMD2<Float>
    ) -> Bool {
        renderer.render(
            frame: frame,
            to: drawable,
            contentMode: contentMode,
            drawableSize: drawableSize,
            zoomScale: zoomScale,
            translation: translation
        )
    }

    func renderMulti(
        frame: IRFFVideoFrame,
        to drawable: CAMetalDrawable,
        drawableSize: CGSize,
        viewports: [CGRect],
        contentModes: [IRGLRenderContentMode],
        zoomScales: [Float],
        translations: [SIMD2<Float>]
    ) -> Bool {
        renderer.renderMulti(
            frame: frame,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports,
            contentModes: contentModes,
            zoomScales: zoomScales,
            translations: translations
        )
    }

    func renderClear(to drawable: CAMetalDrawable) {
        renderer.renderClear(to: drawable)
    }

    func renderFish2Pano(
        frame: IRFFVideoFrame,
        params: IRMetalRenderer.Fish2PanoParams,
        texUVTextures: [MTLTexture],
        to drawable: CAMetalDrawable,
        drawableSize: CGSize,
        viewport: CGRect,
        contentMode: IRGLRenderContentMode,
        outputSize: CGSize,
        zoomScale: Float,
        translation: SIMD2<Float>
    ) -> Bool {
        renderer.renderFish2Pano(
            frame: frame,
            params: params,
            texUVTextures: texUVTextures,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport,
            contentMode: contentMode,
            outputSize: outputSize,
            zoomScale: zoomScale,
            translation: translation
        )
    }

    func renderDistortion(
        frame: IRFFVideoFrame,
        leftMesh: IRMetalDistortionMesh,
        rightMesh: IRMetalDistortionMesh,
        to drawable: CAMetalDrawable,
        drawableSize: CGSize,
        contentMode: IRGLRenderContentMode
    ) -> Bool {
        renderer.renderDistortion(
            frame: frame,
            leftMesh: leftMesh,
            rightMesh: rightMesh,
            to: drawable,
            drawableSize: drawableSize,
            contentMode: contentMode
        )
    }

    func renderFisheye(
        frame: IRFFVideoFrame,
        mesh: IRMetalFisheyeMesh,
        mvp: simd_float4x4,
        textureMatrix: simd_float4x4,
        to drawable: CAMetalDrawable,
        drawableSize: CGSize,
        viewport: CGRect
    ) -> Bool {
        renderer.renderFisheye(
            frame: frame,
            mesh: mesh,
            mvp: mvp,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewport: viewport
        )
    }

    func renderFisheyeMulti(
        frame: IRFFVideoFrame,
        mesh: IRMetalFisheyeMesh,
        mvpList: [simd_float4x4],
        textureMatrix: simd_float4x4,
        to drawable: CAMetalDrawable,
        drawableSize: CGSize,
        viewports: [CGRect]
    ) -> Bool {
        renderer.renderFisheyeMulti(
            frame: frame,
            mesh: mesh,
            mvpList: mvpList,
            textureMatrix: textureMatrix,
            to: drawable,
            drawableSize: drawableSize,
            viewports: viewports
        )
    }
}

private final class IRGLRenderStrategy2D: IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyFish2Pano:
    IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyDistortion:
    IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyFisheye:
    IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyVR: IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyMulti4P:
    IRGLRenderStrategyBase {}

enum IRGLRenderStrategyKind: Equatable {
    case twoD
    case fish2Pano
    case distortion
    case fisheye
    case vr
    case multi4P
}

final class IRGLRenderStrategyFactory {
    static func strategyKind(
        for renderMode: IRGLRenderMode
    ) -> IRGLRenderStrategyKind {
        if renderMode is IRGLRenderModeDistortion {
            return .distortion
        }
        if renderMode is IRGLRenderMode2DFisheye2Pano {
            return .fish2Pano
        }
        if renderMode is IRGLRenderModeVR {
            return .vr
        }
        if renderMode is IRGLRenderModeMulti4P {
            return .multi4P
        }
        if renderMode is IRGLRenderMode3DFisheye {
            return .fisheye
        }
        return .twoD
    }

    static func make(
        for renderMode: IRGLRenderMode,
        renderer: IRMetalRenderer
    ) -> IRGLRenderInternal {
        switch strategyKind(for: renderMode) {
        case .distortion:
            return IRGLRenderStrategyDistortion(renderer: renderer)
        case .fish2Pano:
            return IRGLRenderStrategyFish2Pano(renderer: renderer)
        case .vr:
            return IRGLRenderStrategyVR(renderer: renderer)
        case .multi4P:
            return IRGLRenderStrategyMulti4P(renderer: renderer)
        case .fisheye:
            return IRGLRenderStrategyFisheye(renderer: renderer)
        case .twoD:
            return IRGLRenderStrategy2D(renderer: renderer)
        }
    }
}

extension IRGLRenderMode {
    func buildIRGLProgram(
        pixelFormat: IRPixelFormat,
        viewprotRange: CGRect,
        parameter: IRMediaParameter?
    ) {
        guard let program = programFactory.createIRGLProgram(
            pixelFormat: pixelFormat,
            viewportRange: viewprotRange,
            parameter: parameter
        ) else {
            self.program = nil
            shiftController.program = nil
            return
        }
        self.program = program
        shiftController.program = program
        setting()
        delegate?.programDidCreate(program)
    }
}
