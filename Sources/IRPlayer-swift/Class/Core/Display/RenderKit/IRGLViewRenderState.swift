//
//  IRGLViewRenderState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import CoreGraphics
import Metal
import QuartzCore
import simd

final class IRGLViewRenderState {
    typealias Fish2PanoTextureUpload = (
        MTLDevice,
        Int,
        Int,
        UnsafeBufferPointer<GLfloat>
    ) -> MTLTexture?

    enum FisheyeMeshKind: Equatable {
        case single
        case multi4P
    }

    struct FisheyeMeshCacheKey: Equatable {
        let kind: FisheyeMeshKind
        let textureWidth: Float
        let textureHeight: Float
        let radiusX: Float
        let radiusY: Float
        let centerX: Float
        let centerY: Float
        let isUp: Bool
        let latitudeMaximum: Float
        let projectionIdentifier: ObjectIdentifier?
        let projectionGeneration: UInt64
        let deviceIdentifier: ObjectIdentifier
    }

    struct VRMeshCacheKey: Equatable {
        let modeIdentifier: ObjectIdentifier
        let projectionIdentifier: ObjectIdentifier
        let projectionGeneration: UInt64
        let deviceIdentifier: ObjectIdentifier
    }

    struct Fish2PanoTextureCacheKey: Equatable {
        let paramsIdentifier: ObjectIdentifier
        let deviceIdentifier: ObjectIdentifier
        let pixelMapConfiguration:
            IRGLFish2PanoPixelMapConfigurationKey

        var inputTextureWidth: Int {
            pixelMapConfiguration.inputTextureWidth
        }

        var inputTextureHeight: Int {
            pixelMapConfiguration.inputTextureHeight
        }
    }

    private(set) var fisheyeMesh: IRMetalFisheyeMesh?
    private(set) var vrMesh: IRMetalFisheyeMesh?
    private(set) var vrMeshCacheKey: VRMeshCacheKey?
    private(set) var fisheyeController: IRGLTransformController3DFisheye?
    private(set) var fisheyeParameter: IRFisheyeParameter?
    private(set) var fisheyeLastSize: CGSize = .zero
    private(set) var fisheyeMeshCacheKey:
        FisheyeMeshCacheKey?
    private(set) var fish2PanoParams: IRGLFish2PanoShaderParams?
    private(set) var fish2PanoTextures: [MTLTexture] = []
    private(set) var fish2PanoLastOutputSize: CGSize = .zero
    private(set) var fish2PanoLastAntialias: Int = 0
    private(set) var fish2PanoTextureCacheKey:
        Fish2PanoTextureCacheKey?
    private(set) var distortionLeftMesh: IRMetalDistortionMesh?
    private(set) var distortionRightMesh: IRMetalDistortionMesh?
    private let fish2PanoTextureUpload:
        Fish2PanoTextureUpload
    private var fish2PanoPixelMapReadyHandler:
        (@Sendable () -> Void)?

    init(
        fish2PanoTextureUpload:
            @escaping Fish2PanoTextureUpload =
                IRGLViewRenderState.makeTexUVTexture
    ) {
        self.fish2PanoTextureUpload =
            fish2PanoTextureUpload
    }

    enum Fish2PanoTextureReadiness: Equatable {
        case invalid
        case waitingForTextures
        case ready(outputSize: CGSize, antialias: Int)
    }

    func reset() {
        fisheyeMesh = nil
        resetVR()
        fisheyeController = nil
        fisheyeParameter = nil
        fisheyeLastSize = .zero
        fisheyeMeshCacheKey = nil
        resetFish2Pano()
        distortionLeftMesh = nil
        distortionRightMesh = nil
    }

    func configureFish2Pano(renderMode: IRGLRenderMode) {
        guard let program = renderMode.program as? IRGLProgram2DFisheye2Pano,
              let params = program.metalFish2PanoParams else {
            resetFish2Pano()
            return
        }

        if fish2PanoParams !== params {
            resetFish2Pano()
        }
        fish2PanoParams = params
        params.setPixelMapReadyHandler(
            fish2PanoPixelMapReadyHandler
        )
        params.ensurePixelMapRequested()
    }

    func configureVR(renderMode: IRGLRenderMode) {
        guard let mode = renderMode as? IRGLRenderModeVR,
              let program = mode.program as? IRGLProgramVR,
              let projection =
                program.mapProjection as? IRGLProjectionVR else {
            resetVR()
            return
        }
        guard let cacheKey = vrMeshCacheKey else {
            return
        }
        let snapshot = projection.meshSnapshot()
        guard cacheKey.modeIdentifier
                == ObjectIdentifier(mode),
              cacheKey.projectionIdentifier
                == ObjectIdentifier(projection),
              cacheKey.projectionGeneration
                == snapshot.generation else {
            resetVR()
            return
        }
    }

    func setFish2PanoPixelMapReadyHandler(
        _ handler: (@Sendable () -> Void)?
    ) {
        fish2PanoPixelMapReadyHandler = handler
        fish2PanoParams?.setPixelMapReadyHandler(handler)
    }

    func prepareFish2PanoTextures(device: MTLDevice?) -> Fish2PanoTextureReadiness? {
        guard let params = fish2PanoParams else { return nil }
        let outputWidth = Int(params.outputWidth)
        let outputHeight = Int(params.outputHeight)
        let antialias = Int(params.antialias)
        guard outputWidth > 0, outputHeight > 0, antialias > 0 else { return .invalid }

        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        if outputSize != fish2PanoLastOutputSize || antialias != fish2PanoLastAntialias {
            fish2PanoTextures = []
            fish2PanoTextureCacheKey = nil
            fish2PanoLastOutputSize = outputSize
            fish2PanoLastAntialias = antialias
        }

        guard let expectedTextureCount =
                IRGLFish2PanoPixelMapGeneration.textureCount(
                    antialias: antialias
                ),
              let expectedElementCount =
                IRGLFish2PanoPixelMapGeneration.elementCount(
                    outputWidth: outputWidth,
                    outputHeight: outputHeight
                ) else {
            return .invalid
        }
        let cachedReadiness = Fish2PanoTextureReadiness.ready(
            outputSize: outputSize,
            antialias: antialias
        )
        let requiredConfiguration =
            params.requiredPixelMapConfigurationKey()
        let requiredConfigurationMatchesLiveLayout: Bool
        if let requiredConfiguration {
            requiredConfigurationMatchesLiveLayout =
                requiredConfiguration.inputTextureWidth
                    == Int(params.textureWidth)
                    && requiredConfiguration.inputTextureHeight
                    == Int(params.textureHeight)
                    && requiredConfiguration.outputWidth
                    == outputWidth
                    && requiredConfiguration.outputHeight
                    == outputHeight
                    && requiredConfiguration.antialias
                    == antialias
        } else {
            requiredConfigurationMatchesLiveLayout = false
        }
        let currentCacheKey = device.flatMap {
            device -> Fish2PanoTextureCacheKey? in
            guard let requiredConfiguration,
                  requiredConfigurationMatchesLiveLayout else {
                return nil
            }
            return Self.fish2PanoTextureCacheKey(
                params: params,
                device: device,
                pixelMapConfiguration:
                    requiredConfiguration
            )
        }
        let hasCoherentTextureCache =
            currentCacheKey != nil
                && fish2PanoTextures.count == expectedTextureCount
                && fish2PanoTextureCacheKey == currentCacheKey
        if let device,
           let pixelMap = params.pixelMapIfReady() {
            guard requiredConfigurationMatchesLiveLayout,
                  pixelMap.outputWidth == outputWidth,
                  pixelMap.outputHeight == outputHeight,
                  pixelMap.antialias == antialias,
                  pixelMap.configurationKey
                    == requiredConfiguration,
                  pixelMap.textureCount
                    == expectedTextureCount,
                  pixelMap.elementCountPerTexture
                    == expectedElementCount else {
                params.acknowledgePixelMap(pixelMap)
                params.updateOutputWH()
                return hasCoherentTextureCache
                    ? cachedReadiness
                    : .waitingForTextures
            }
            var newTextures: [MTLTexture] = []
            newTextures.reserveCapacity(expectedTextureCount)
            for i in 0..<expectedTextureCount {
                var uploadedTexture: MTLTexture?
                let borrowed: Bool? =
                    pixelMap.withUnsafeMapBuffer(at: i) {
                        buffer in
                        uploadedTexture =
                            fish2PanoTextureUpload(
                                device,
                                outputWidth,
                                outputHeight,
                                buffer
                            )
                        return true
                    }
                guard borrowed == true,
                      let uploadedTexture else {
                    return hasCoherentTextureCache
                        ? cachedReadiness
                        : .waitingForTextures
                }
                newTextures.append(uploadedTexture)
            }
            let installedCacheKey =
                Self.fish2PanoTextureCacheKey(
                    params: params,
                    device: device,
                    pixelMapConfiguration:
                        pixelMap.configurationKey
                )
            fish2PanoTextures = newTextures
            fish2PanoTextureCacheKey =
                installedCacheKey
            params.acknowledgePixelMap(pixelMap)
        }

        guard currentCacheKey != nil,
              fish2PanoTextures.count == expectedTextureCount,
              fish2PanoTextureCacheKey == currentCacheKey else {
            return .waitingForTextures
        }

        return .ready(outputSize: outputSize, antialias: antialias)
    }

    func configureFisheye(renderMode: IRGLRenderMode, viewportSize: CGSize) {
        guard renderMode is IRGLRenderMode3DFisheye else {
            resetFisheye()
            return
        }

        if let programController = renderMode.program?.tramsformController as? IRGLTransformController3DFisheye {
            fisheyeController = programController
        } else {
            let width = max(Int(viewportSize.width), 1)
            let height = max(Int(viewportSize.height), 1)
            fisheyeController = IRGLTransformController3DFisheye(viewportWidth: width,
                                                                 viewportHeight: height,
                                                                 tileType: .backward)
        }

        if let parameter = renderMode.parameter as? IRFisheyeParameter {
            fisheyeParameter = parameter
        } else {
            fisheyeParameter = Self.defaultFisheyeParameter()
        }
    }

    func resetFisheyeViewport(width: Int, height: Int, resetTransform: Bool) {
        fisheyeController?.resetViewport(width: width,
                                         height: height,
                                         resetTransform: resetTransform)
    }

    func updateFallbackFisheye(fx: Float, fy: Float, sx: Float, sy: Float) {
        fisheyeController?.update(fx: fx, fy: fy, sx: sx, sy: sy)
    }

    func scrollFallbackFisheye(dx: Float, dy: Float) {
        fisheyeController?.scroll(dx: dx, dy: dy)
    }

    func scrollFallbackFisheye(degreeX: Float, degreeY: Float) {
        fisheyeController?.scroll(degreeX: degreeX, degreeY: degreeY)
    }

    func renderMulti4PIfNeeded(frame: IRFFVideoFrame,
                               mode: IRGLRenderMode?,
                               renderer: IRGLRenderInternal,
                               drawable: CAMetalDrawable,
                               drawableSize: CGSize,
                               device: MTLDevice?,
                               completion:
                                   @escaping IRGLRenderCompletion) -> Bool? {
        guard mode is IRGLRenderModeMulti4P else {
            return nil
        }
        guard let program =
                mode?.program as? IRGLProgramMulti4P else {
            return false
        }
        if program.programs.first is IRGLProgram3DFisheye {
            let parameter = (mode?.parameter as? IRFisheyeParameter) ?? Self.defaultFisheyeParameter()
            let dimensions = frame.dimensionSnapshot()
            let textureWidth = parameter.width > 0
                ? parameter.width
                : Float(dimensions.width)
            let textureHeight = parameter.height > 0
                ? parameter.height
                : Float(dimensions.height)
            let meshSize = CGSize(width: CGFloat(textureWidth), height: CGFloat(textureHeight))
            let projection =
                program.programs.first?.mapProjection
                    as? IRGLProjectionEquirectangular
            guard let mesh = prepareFisheyeMesh(
                kind: .multi4P,
                textureWidth: textureWidth,
                textureHeight: textureHeight,
                meshSize: meshSize,
                parameter: parameter,
                projection: projection,
                device: device
            ) else {
                return false
            }
            let texMatrix = IRMatrix4.makeScale(1, -1, 1)
            let viewports = program.programs.map { $0.viewprotRange }
            var mvps: [simd_float4x4] = []
            mvps.reserveCapacity(program.programs.count)
            for program in program.programs {
                if let controller = program.tramsformController as? IRGLTransformController3DFisheye {
                    mvps.append(controller.getModelViewProjectionMatrix().toMetalClipSpace())
                } else {
                    mvps.append(IRMatrix4.identity().toMetalClipSpace())
                }
            }

            return renderer.renderFisheyeMulti(frame: frame,
                                               mesh: mesh,
                                               mvpList: mvps,
                                               textureMatrix: texMatrix,
                                               to: drawable,
                                               drawableSize: drawableSize,
                                               viewports: viewports,
                                               completion: completion)
        } else {
            let viewports = program.programs.map { $0.viewprotRange }
            let contentModes = program.programs.map { $0.contentMode }
            let zoomScales = program.programs.map { Float($0.getCurrentScale().x) }
            let translations = program.programs.map {
                IRGLFrameSubmissionSession.translationVector(
                    for: $0.tramsformController?.getScope()
                )
            }
            return renderer.renderMulti(frame: frame,
                                        to: drawable,
                                        drawableSize: drawableSize,
                                        viewports: viewports,
                                        contentModes: contentModes,
                                        zoomScales: zoomScales,
                                        translations: translations,
                                        completion: completion)
        }
    }

    func renderFish2PanoIfNeeded(frame: IRFFVideoFrame,
                                 mode: IRGLRenderMode?,
                                 renderer: IRGLRenderInternal,
                                 drawable: CAMetalDrawable,
                                 drawableSize: CGSize,
                                 renderContentMode: IRGLRenderContentMode,
                                 device: MTLDevice?,
                                 completion:
                                     @escaping IRGLRenderCompletion) -> Bool? {
        guard mode is IRGLRenderMode2DFisheye2Pano else { return nil }
        guard let readiness = prepareFish2PanoTextures(device: device) else { return false }

        let outputSize: CGSize
        let antialias: Int
        switch readiness {
        case .invalid:
            return false
        case .waitingForTextures:
            return false
        case let .ready(readyOutputSize, readyAntialias):
            outputSize = readyOutputSize
            antialias = readyAntialias
        }

        guard let params = fish2PanoParams else { return false }
        let outputWidth = Int(outputSize.width)
        let outputHeight = Int(outputSize.height)

        let viewportRect: CGRect
        if let panoProgram = mode?.program as? IRGLProgram2DFisheye2Pano {
            viewportRect = panoProgram.viewprotRange
        } else {
            viewportRect = (mode?.program as? IRGLProgram2D)?.calculateViewport() ??
                CGRect(x: 0, y: 0, width: drawableSize.width, height: drawableSize.height)
        }

        let renderParams = IRMetalRenderer.Fish2PanoParams(
            fishwidth: Int32(params.textureWidth),
            fishheight: Int32(params.textureHeight),
            panowidth: Int32(outputWidth),
            panoheight: Int32(outputHeight),
            antialias: Int32(antialias),
            offsetX: params.offsetX
        )

        let effectiveProgram = mode?.program as? IRGLProgram2D
        let effectiveContentMode = effectiveProgram?.contentMode ?? renderContentMode
        let zoomScale = effectiveProgram?.getCurrentScale().x ?? 1
        return renderer.renderFish2Pano(frame: frame,
                                        params: renderParams,
                                        texUVTextures: fish2PanoTextures,
                                        to: drawable,
                                        drawableSize: drawableSize,
                                        viewport: viewportRect,
                                        contentMode: effectiveContentMode,
                                        outputSize: outputSize,
                                        zoomScale: Float(zoomScale),
                                        translation:
                                            IRGLFrameSubmissionSession
                                            .translationVector(
                                                for: effectiveProgram?
                                                    .tramsformController?
                                                    .getScope()
                                            ),
                                        completion: completion)
    }

    func renderDistortionIfNeeded(frame: IRFFVideoFrame,
                                  mode: IRGLRenderMode?,
                                  renderer: IRGLRenderInternal,
                                  drawable: CAMetalDrawable,
                                  drawableSize: CGSize,
                                  renderContentMode: IRGLRenderContentMode,
                                  device: MTLDevice?,
                                  completion:
                                      @escaping IRGLRenderCompletion) -> Bool? {
        guard mode is IRGLRenderModeDistortion else { return nil }
        if distortionLeftMesh == nil || distortionRightMesh == nil {
            guard let device = device ?? MTLCreateSystemDefaultDevice() else { return false }
            distortionLeftMesh = IRMetalDistortionMesh(device: device, modelType: .left)
            distortionRightMesh = IRMetalDistortionMesh(device: device, modelType: .right)
        }
        guard let leftMesh = distortionLeftMesh, let rightMesh = distortionRightMesh else { return false }
        let effectiveContentMode = (mode?.program as? IRGLProgram2D)?.contentMode ?? renderContentMode
        return renderer.renderDistortion(frame: frame,
                                         leftMesh: leftMesh,
                                         rightMesh: rightMesh,
                                         to: drawable,
                                         drawableSize: drawableSize,
                                         contentMode: effectiveContentMode,
                                         completion: completion)
    }

    func renderFisheyeIfNeeded(frame: IRFFVideoFrame,
                               mode: IRGLRenderMode?,
                               renderer: IRGLRenderInternal,
                               drawable: CAMetalDrawable,
                               drawableSize: CGSize,
                               device: MTLDevice?,
                               completion:
                                   @escaping IRGLRenderCompletion) -> Bool? {
        guard mode is IRGLRenderMode3DFisheye else { return nil }
        guard let controller = fisheyeController else { return false }
        guard let parameter = fisheyeParameter else { return false }

        let dimensions = frame.dimensionSnapshot()
        let textureWidth = parameter.width > 0
            ? parameter.width
            : Float(dimensions.width)
        let textureHeight = parameter.height > 0
            ? parameter.height
            : Float(dimensions.height)
        let meshSize = CGSize(width: CGFloat(textureWidth), height: CGFloat(textureHeight))
        let projection =
            mode?.program?.mapProjection
                as? IRGLProjectionEquirectangular
        guard let mesh = prepareFisheyeMesh(
            kind: .single,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            meshSize: meshSize,
            parameter: parameter,
            projection: projection,
            device: device
        ) else {
            return false
        }
        let mvp = controller.getModelViewProjectionMatrix()
        let texMatrix = IRMatrix4.makeScale(1, -1, 1)

        let viewportRect = (mode?.program as? IRGLProgram2D)?.calculateViewport() ??
            CGRect(x: 0, y: 0, width: drawableSize.width, height: drawableSize.height)

        return renderer.renderFisheye(frame: frame,
                                      mesh: mesh,
                                      mvp: mvp.toMetalClipSpace(),
                                      textureMatrix: texMatrix,
                                      to: drawable,
                                      drawableSize: drawableSize,
                                      viewport: viewportRect,
                                      completion: completion)
    }

    func renderVRIfNeeded(frame: IRFFVideoFrame,
                          mode: IRGLRenderMode?,
                          renderer: IRGLRenderInternal,
                          drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          device: MTLDevice?,
                          completion:
                              @escaping IRGLRenderCompletion) -> Bool? {
        guard let mode = mode as? IRGLRenderModeVR else {
            return nil
        }
        guard let program = mode.program as? IRGLProgramVR else {
            return false
        }
        guard let controller = program.tramsformController as? IRGLTransformControllerVR else {
            return false
        }

        guard let projection =
                program.mapProjection as? IRGLProjectionVR,
              let device =
                device ?? MTLCreateSystemDefaultDevice() else {
            resetVR()
            return false
        }
        let snapshot = projection.meshSnapshot()
        let cacheKey = VRMeshCacheKey(
            modeIdentifier: ObjectIdentifier(mode),
            projectionIdentifier:
                ObjectIdentifier(projection),
            projectionGeneration: snapshot.generation,
            deviceIdentifier: ObjectIdentifier(device)
        )
        let mesh: IRMetalFisheyeMesh
        if vrMeshCacheKey == cacheKey,
           let cachedMesh = vrMesh {
            mesh = cachedMesh
        } else {
            guard let candidate = IRMetalFisheyeMesh(
                device: device,
                positions: snapshot.mesh.positions,
                texcoords: snapshot.mesh.texcoords,
                indices: snapshot.mesh.indices
            ) else {
                resetVR()
                return false
            }
            vrMesh = candidate
            vrMeshCacheKey = cacheKey
            mesh = candidate
        }
        let mvp = controller.getModelViewProjectionMatrix()
        let texMatrix = IRMatrix4.identity()
        let viewportRect = program.calculateViewport()
        let mvpAdjusted = mvp.toMetalClipSpace()
        let rendered = renderer.renderFisheye(frame: frame,
                                              mesh: mesh,
                                              mvp: mvpAdjusted,
                                              textureMatrix: texMatrix,
                                              to: drawable,
                                              drawableSize: drawableSize,
                                              viewport: viewportRect,
                                              completion: completion)
        return rendered
    }

    private func resetFish2Pano() {
        fish2PanoParams?.setPixelMapReadyHandler(nil)
        fish2PanoParams = nil
        fish2PanoTextures = []
        fish2PanoTextureCacheKey = nil
        fish2PanoLastOutputSize = .zero
        fish2PanoLastAntialias = 0
    }

    private static func fish2PanoTextureCacheKey(
        params: IRGLFish2PanoShaderParams,
        device: MTLDevice,
        pixelMapConfiguration:
            IRGLFish2PanoPixelMapConfigurationKey
    ) -> Fish2PanoTextureCacheKey {
        Fish2PanoTextureCacheKey(
            paramsIdentifier: ObjectIdentifier(params),
            deviceIdentifier: ObjectIdentifier(device),
            pixelMapConfiguration:
                pixelMapConfiguration
        )
    }

    private func resetVR() {
        vrMesh = nil
        vrMeshCacheKey = nil
    }

    private func resetFisheye() {
        fisheyeController = nil
        fisheyeMesh = nil
        fisheyeParameter = nil
        fisheyeLastSize = .zero
        fisheyeMeshCacheKey = nil
    }

    private func prepareFisheyeMesh(
        kind: FisheyeMeshKind,
        textureWidth: Float,
        textureHeight: Float,
        meshSize: CGSize,
        parameter: IRFisheyeParameter,
        projection: IRGLProjectionEquirectangular?,
        device: MTLDevice?
    ) -> IRMetalFisheyeMesh? {
        guard let device =
                device ?? MTLCreateSystemDefaultDevice() else {
            fisheyeMesh = nil
            fisheyeMeshCacheKey = nil
            fisheyeLastSize = .zero
            return nil
        }

        let projectionDiagnostics = projection?.diagnostics
        let cacheKey = FisheyeMeshCacheKey(
            kind: kind,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            radiusX: parameter.rx,
            radiusY: parameter.ry,
            centerX: parameter.cx,
            centerY: parameter.cy,
            isUp: parameter.up,
            latitudeMaximum: parameter.latmax,
            projectionIdentifier:
                projection.map(ObjectIdentifier.init),
            projectionGeneration:
                projectionDiagnostics?.generation ?? 0,
            deviceIdentifier:
                ObjectIdentifier(device)
        )
        if fisheyeMeshCacheKey == cacheKey,
           let fisheyeMesh {
            return fisheyeMesh
        }

        let candidate: IRMetalFisheyeMesh?
        if let projection,
           let meshData = projection.exportMesh() {
            candidate = IRMetalFisheyeMesh(
                device: device,
                positions: meshData.positions,
                texcoords: meshData.texcoords,
                indices: meshData.indices
            )
        } else {
            candidate = IRMetalFisheyeMesh(
                device: device,
                textureWidth: textureWidth,
                textureHeight: textureHeight,
                centerX: parameter.cx,
                centerY: parameter.cy,
                radius: parameter.ry
            )
        }

        fisheyeMesh = candidate
        fisheyeLastSize =
            candidate == nil ? .zero : meshSize
        fisheyeMeshCacheKey =
            candidate == nil ? nil : cacheKey
        return candidate
    }

    static func makeTexUVTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        data: UnsafeBufferPointer<GLfloat>
    ) -> MTLTexture? {
        guard let layout = Self.texUVTextureLayout(
            width: width,
            height: height
        ),
        let baseAddress = data.baseAddress,
        data.count
            == layout.totalByteCount
                / MemoryLayout<GLfloat>.stride else {
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: baseAddress,
                        bytesPerRow: layout.bytesPerRow)
        return texture
    }

    static func defaultFisheyeParameter() -> IRFisheyeParameter {
        IRFisheyeParameter(width: 0,
                           height: 0,
                           up: false,
                           rx: 0,
                           ry: 0,
                           cx: 0,
                           cy: 0,
                           latmax: 0)
    }

    static func texUVTextureLayout(
        width: Int,
        height: Int
    ) -> (bytesPerRow: Int, totalByteCount: Int)? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerTexel = MemoryLayout<Float>.size * 2
        let (bytesPerRow, rowOverflow) =
            width.multipliedReportingOverflow(by: bytesPerTexel)
        guard !rowOverflow, bytesPerRow > 0 else { return nil }
        let (totalByteCount, totalOverflow) =
            bytesPerRow.multipliedReportingOverflow(by: height)
        guard !totalOverflow, totalByteCount > 0 else { return nil }
        return (bytesPerRow, totalByteCount)
    }
}
