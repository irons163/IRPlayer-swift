//
//  IRMetalRendererResources.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import CoreVideo
import Foundation
import Metal

enum IRMetalRendererPipelineKind: String, CaseIterable, Equatable {
    case nv12
    case i420
    case rgb
    case nv12Mesh
    case i420Mesh
    case rgbMesh
    case nv12Fish2Pano
    case i420Fish2Pano
    case rgbFish2Pano
    case distortion
}

enum IRMetalRendererBuildFailure: Error, Equatable {
    case missingTextureCache
    case missingShaderLibrary
    case missingShaderFunction(String)
    case pipeline(IRMetalRendererPipelineKind)
    case quadBuffer(IRMetalRenderer.QuadTextureRange)
}

struct IRMetalRendererResourceDependencies {
    let makeTextureCache: (MTLDevice) -> CVMetalTextureCache?
    let makeLibrary: (MTLDevice) -> MTLLibrary?
    let makeFunction: (MTLLibrary, String) -> MTLFunction?
    let makePipelineState:
        (MTLDevice, IRMetalRendererPipelineKind, MTLRenderPipelineDescriptor)
        -> MTLRenderPipelineState?
    let makeQuadBuffer:
        (MTLDevice, IRMetalRenderer.QuadTextureRange, [IRMetalRenderer.QuadVertex])
        -> MTLBuffer?

    static var system: IRMetalRendererResourceDependencies {
        IRMetalRendererResourceDependencies(
            makeTextureCache: { device in
                var textureCache: CVMetalTextureCache?
                let status = CVMetalTextureCacheCreate(
                    kCFAllocatorDefault,
                    nil,
                    device,
                    nil,
                    &textureCache
                )
                guard status == kCVReturnSuccess else {
                    return nil
                }
                return textureCache
            },
            makeLibrary: { device in
                #if SWIFT_PACKAGE
                return (try? device.makeDefaultLibrary(bundle: .module))
                    ?? (try? device.makeDefaultLibrary())
                #else
                return (
                    try? device.makeDefaultLibrary(
                        bundle: Bundle(for: IRMetalRenderer.self)
                    )
                ) ?? device.makeDefaultLibrary()
                #endif
            },
            makeFunction: { library, name in
                library.makeFunction(name: name)
            },
            makePipelineState: { device, kind, descriptor in
                do {
                    return try device.makeRenderPipelineState(
                        descriptor: descriptor
                    )
                } catch {
                    IRMetalRuntimeDebugOutput.write(
                        "IRMetalRenderer: failed to create \(kind.rawValue) "
                            + "pipeline: \(error)"
                    )
                    return nil
                }
            },
            makeQuadBuffer: { device, _, vertices in
                device.makeBuffer(
                    bytes: vertices,
                    length: MemoryLayout<IRMetalRenderer.QuadVertex>.stride
                        * vertices.count,
                    options: .storageModeShared
                )
            }
        )
    }
}

final class IRMetalRendererResources {
    struct Pipelines {
        let nv12: MTLRenderPipelineState
        let i420: MTLRenderPipelineState
        let rgb: MTLRenderPipelineState
        let nv12Mesh: MTLRenderPipelineState
        let i420Mesh: MTLRenderPipelineState
        let rgbMesh: MTLRenderPipelineState
        let nv12Fish2Pano: MTLRenderPipelineState
        let i420Fish2Pano: MTLRenderPipelineState
        let rgbFish2Pano: MTLRenderPipelineState
        let distortion: MTLRenderPipelineState
    }

    struct QuadBuffers {
        let full: MTLBuffer
        let left: MTLBuffer
        let right: MTLBuffer
    }

    struct Diagnostics: Equatable {
        let hasTextureCache: Bool
        let pipelineCount: Int
        let quadBufferCount: Int
    }

    let textureCache: CVMetalTextureCache
    let pipelines: Pipelines
    let quadBuffers: QuadBuffers

    private init(
        textureCache: CVMetalTextureCache,
        pipelines: Pipelines,
        quadBuffers: QuadBuffers
    ) {
        self.textureCache = textureCache
        self.pipelines = pipelines
        self.quadBuffers = quadBuffers
    }

    var diagnostics: Diagnostics {
        Diagnostics(
            hasTextureCache: true,
            pipelineCount: IRMetalRendererPipelineKind.allCases.count,
            quadBufferCount: 3
        )
    }

    static func make(
        device: MTLDevice,
        dependencies: IRMetalRendererResourceDependencies = .system
    ) -> Result<IRMetalRendererResources, IRMetalRendererBuildFailure> {
        do {
            return .success(
                try build(
                    device: device,
                    dependencies: dependencies
                )
            )
        } catch let failure as IRMetalRendererBuildFailure {
            IRMetalRuntimeDebugOutput.write(
                "IRMetalRenderer: resource bootstrap failed: \(failure)"
            )
            return .failure(failure)
        } catch {
            preconditionFailure(
                "IRMetalRenderer resource builder emitted an unknown error"
            )
        }
    }

    private static func build(
        device: MTLDevice,
        dependencies: IRMetalRendererResourceDependencies
    ) throws -> IRMetalRendererResources {
        guard let textureCache =
                dependencies.makeTextureCache(device) else {
            throw IRMetalRendererBuildFailure.missingTextureCache
        }
        guard let library = dependencies.makeLibrary(device) else {
            throw IRMetalRendererBuildFailure.missingShaderLibrary
        }

        func function(_ name: String) throws -> MTLFunction {
            guard let function =
                    dependencies.makeFunction(library, name) else {
                throw IRMetalRendererBuildFailure
                    .missingShaderFunction(name)
            }
            return function
        }

        let vertex = try function("irVertex")
        let vertex3D = try function("irVertex3D")
        let fragmentNV12 = try function("irFragmentNV12")
        let fragmentI420 = try function("irFragmentI420")
        let fragmentRGB = try function("irFragmentRGB")
        let fragmentFish2PanoNV12 =
            try function("irFragmentFish2PanoNV12")
        let fragmentFish2PanoI420 =
            try function("irFragmentFish2PanoI420")
        let fragmentFish2PanoRGB =
            try function("irFragmentFish2PanoRGB")
        let vertexDistortion = try function("irDistortionVertex")
        let fragmentDistortion = try function("irFragmentDistortion")

        func pipeline(
            _ kind: IRMetalRendererPipelineKind,
            vertexFunction: MTLFunction,
            fragmentFunction: MTLFunction,
            vertexDescriptor: MTLVertexDescriptor
        ) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
            guard let pipeline = dependencies.makePipelineState(
                device,
                kind,
                descriptor
            ) else {
                throw IRMetalRendererBuildFailure.pipeline(kind)
            }
            return pipeline
        }

        let descriptor2D = make2DVertexDescriptor()
        let descriptor3D = make3DVertexDescriptor()
        let descriptorDistortion = makeDistortionVertexDescriptor()
        let pipelines = Pipelines(
            nv12: try pipeline(
                .nv12,
                vertexFunction: vertex,
                fragmentFunction: fragmentNV12,
                vertexDescriptor: descriptor2D
            ),
            i420: try pipeline(
                .i420,
                vertexFunction: vertex,
                fragmentFunction: fragmentI420,
                vertexDescriptor: descriptor2D
            ),
            rgb: try pipeline(
                .rgb,
                vertexFunction: vertex,
                fragmentFunction: fragmentRGB,
                vertexDescriptor: descriptor2D
            ),
            nv12Mesh: try pipeline(
                .nv12Mesh,
                vertexFunction: vertex3D,
                fragmentFunction: fragmentNV12,
                vertexDescriptor: descriptor3D
            ),
            i420Mesh: try pipeline(
                .i420Mesh,
                vertexFunction: vertex3D,
                fragmentFunction: fragmentI420,
                vertexDescriptor: descriptor3D
            ),
            rgbMesh: try pipeline(
                .rgbMesh,
                vertexFunction: vertex3D,
                fragmentFunction: fragmentRGB,
                vertexDescriptor: descriptor3D
            ),
            nv12Fish2Pano: try pipeline(
                .nv12Fish2Pano,
                vertexFunction: vertex,
                fragmentFunction: fragmentFish2PanoNV12,
                vertexDescriptor: descriptor2D
            ),
            i420Fish2Pano: try pipeline(
                .i420Fish2Pano,
                vertexFunction: vertex,
                fragmentFunction: fragmentFish2PanoI420,
                vertexDescriptor: descriptor2D
            ),
            rgbFish2Pano: try pipeline(
                .rgbFish2Pano,
                vertexFunction: vertex,
                fragmentFunction: fragmentFish2PanoRGB,
                vertexDescriptor: descriptor2D
            ),
            distortion: try pipeline(
                .distortion,
                vertexFunction: vertexDistortion,
                fragmentFunction: fragmentDistortion,
                vertexDescriptor: descriptorDistortion
            )
        )

        func quadBuffer(
            _ range: IRMetalRenderer.QuadTextureRange
        ) throws -> MTLBuffer {
            let vertices = IRMetalRenderer.quadVertices(
                textureRange: range
            )
            guard let buffer = dependencies.makeQuadBuffer(
                device,
                range,
                vertices
            ) else {
                throw IRMetalRendererBuildFailure.quadBuffer(range)
            }
            return buffer
        }

        let quadBuffers = QuadBuffers(
            full: try quadBuffer(.full),
            left: try quadBuffer(.left),
            right: try quadBuffer(.right)
        )
        return IRMetalRendererResources(
            textureCache: textureCache,
            pipelines: pipelines,
            quadBuffers: quadBuffers
        )
    }

    private static func make2DVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float2
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset =
            MemoryLayout<SIMD2<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride =
            MemoryLayout<SIMD2<Float>>.stride * 2
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }

    private static func makeDistortionVertexDescriptor()
        -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float2
        descriptor.attributes[0].offset =
            MemoryLayout<IRMetalDistortionVertex>.offset(
                of: \.position
            ) ?? 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float
        descriptor.attributes[1].offset =
            MemoryLayout<IRMetalDistortionVertex>.offset(
                of: \.vignette
            ) ?? 0
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset =
            MemoryLayout<IRMetalDistortionVertex>.offset(
                of: \.redTexCoord
            ) ?? 0
        descriptor.attributes[2].bufferIndex = 0
        descriptor.attributes[3].format = .float2
        descriptor.attributes[3].offset =
            MemoryLayout<IRMetalDistortionVertex>.offset(
                of: \.greenTexCoord
            ) ?? 0
        descriptor.attributes[3].bufferIndex = 0
        descriptor.attributes[4].format = .float2
        descriptor.attributes[4].offset =
            MemoryLayout<IRMetalDistortionVertex>.offset(
                of: \.blueTexCoord
            ) ?? 0
        descriptor.attributes[4].bufferIndex = 0
        descriptor.layouts[0].stride =
            MemoryLayout<IRMetalDistortionVertex>.stride
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }

    private static func make3DVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset =
            MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride =
            MemoryLayout<IRMetalFisheyeMesh.Vertex>.stride
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }
}
