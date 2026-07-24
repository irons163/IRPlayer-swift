//
//  IRMetalRendererResourcesTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/7/24.
//

import CoreVideo
import Metal
import XCTest
@testable import IRPlayer_swift

final class IRMetalRendererResourcesTests: XCTestCase {
    private typealias ResourceDependencies =
        IRMetalRendererResourceDependencies

    private func makeDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        return device
    }

    private func makeDependencies(
        makeTextureCache:
            ((MTLDevice) -> CVMetalTextureCache?)? = nil,
        makeLibrary:
            ((MTLDevice) -> MTLLibrary?)? = nil,
        makeFunction:
            ((MTLLibrary, String) -> MTLFunction?)? = nil,
        makePipelineState:
            ((
                MTLDevice,
                IRMetalRendererPipelineKind,
                MTLRenderPipelineDescriptor
            ) -> MTLRenderPipelineState?)? = nil,
        makeQuadBuffer:
            ((
                MTLDevice,
                IRMetalRenderer.QuadTextureRange,
                [IRMetalRenderer.QuadVertex]
            ) -> MTLBuffer?)? = nil
    ) -> ResourceDependencies {
        let system = ResourceDependencies.system
        return ResourceDependencies(
            makeTextureCache:
                makeTextureCache ?? system.makeTextureCache,
            makeLibrary: makeLibrary ?? system.makeLibrary,
            makeFunction: makeFunction ?? system.makeFunction,
            makePipelineState:
                makePipelineState ?? system.makePipelineState,
            makeQuadBuffer:
                makeQuadBuffer ?? system.makeQuadBuffer
        )
    }

    func testSystemBootstrapPublishesOneCompleteGeneration() throws {
        let device = try makeDevice()

        let result = IRMetalRendererResources.make(device: device)

        guard case let .success(resources) = result else {
            return XCTFail("Expected complete renderer resources")
        }
        XCTAssertEqual(
            resources.diagnostics,
            .init(
                hasTextureCache: true,
                pipelineCount: 10,
                quadBufferCount: 3
            )
        )
        XCTAssertGreaterThan(resources.quadBuffers.full.length, 0)
        XCTAssertGreaterThan(resources.quadBuffers.left.length, 0)
        XCTAssertGreaterThan(resources.quadBuffers.right.length, 0)
    }

    func testCompleteBuildRunsEveryRequiredStageExactlyOnce()
        throws {
        let device = try makeDevice()
        let system = ResourceDependencies.system
        var textureCacheCallCount = 0
        var libraryCallCount = 0
        var functionNames: [String] = []
        var pipelineKinds: [IRMetalRendererPipelineKind] = []
        var quadRanges:
            [IRMetalRenderer.QuadTextureRange] = []
        let dependencies = makeDependencies(
            makeTextureCache: { device in
                textureCacheCallCount += 1
                return system.makeTextureCache(device)
            },
            makeLibrary: { device in
                libraryCallCount += 1
                return system.makeLibrary(device)
            },
            makeFunction: { library, name in
                functionNames.append(name)
                return system.makeFunction(library, name)
            },
            makePipelineState: { device, kind, descriptor in
                pipelineKinds.append(kind)
                return system.makePipelineState(
                    device,
                    kind,
                    descriptor
                )
            },
            makeQuadBuffer: { device, range, vertices in
                quadRanges.append(range)
                return system.makeQuadBuffer(
                    device,
                    range,
                    vertices
                )
            }
        )

        let result = IRMetalRendererResources.make(
            device: device,
            dependencies: dependencies
        )

        guard case .success = result else {
            return XCTFail("Expected complete resources")
        }
        XCTAssertEqual(textureCacheCallCount, 1)
        XCTAssertEqual(libraryCallCount, 1)
        XCTAssertEqual(functionNames.count, 10)
        XCTAssertEqual(
            pipelineKinds,
            IRMetalRendererPipelineKind.allCases
        )
        XCTAssertEqual(quadRanges, [.full, .left, .right])
    }

    func testMissingTextureCacheStopsBeforeLibraryConstruction()
        throws {
        let device = try makeDevice()
        var libraryCallCount = 0
        let dependencies = makeDependencies(
            makeTextureCache: { _ in nil },
            makeLibrary: { _ in
                libraryCallCount += 1
                return nil
            }
        )

        let result = IRMetalRendererResources.make(
            device: device,
            dependencies: dependencies
        )

        guard case let .failure(failure) = result else {
            return XCTFail("Expected texture-cache failure")
        }
        XCTAssertEqual(failure, .missingTextureCache)
        XCTAssertEqual(libraryCallCount, 0)
    }

    func testMissingLibraryStopsBeforeFunctionConstruction() throws {
        let device = try makeDevice()
        var functionCallCount = 0
        let dependencies = makeDependencies(
            makeLibrary: { _ in nil },
            makeFunction: { _, _ in
                functionCallCount += 1
                return nil
            }
        )

        let result = IRMetalRendererResources.make(
            device: device,
            dependencies: dependencies
        )

        guard case let .failure(failure) = result else {
            return XCTFail("Expected shader-library failure")
        }
        XCTAssertEqual(failure, .missingShaderLibrary)
        XCTAssertEqual(functionCallCount, 0)
    }

    func testMissingFunctionReportsExactNameBeforePipelineCreation()
        throws {
        let device = try makeDevice()
        let system = ResourceDependencies.system
        var pipelineCallCount = 0
        let dependencies = makeDependencies(
            makeFunction: { library, name in
                guard name != "irFragmentFish2PanoI420" else {
                    return nil
                }
                return system.makeFunction(library, name)
            },
            makePipelineState: { device, kind, descriptor in
                pipelineCallCount += 1
                return system.makePipelineState(
                    device,
                    kind,
                    descriptor
                )
            }
        )

        let result = IRMetalRendererResources.make(
            device: device,
            dependencies: dependencies
        )

        guard case let .failure(failure) = result else {
            return XCTFail("Expected shader-function failure")
        }
        XCTAssertEqual(
            failure,
            .missingShaderFunction(
                "irFragmentFish2PanoI420"
            )
        )
        XCTAssertEqual(pipelineCallCount, 0)
    }

    func testPipelineFailureReportsExactKindBeforeBufferConstruction()
        throws {
        let device = try makeDevice()
        let system = ResourceDependencies.system
        var bufferCallCount = 0
        let dependencies = makeDependencies(
            makePipelineState: { device, kind, descriptor in
                guard kind != .rgbMesh else {
                    return nil
                }
                return system.makePipelineState(
                    device,
                    kind,
                    descriptor
                )
            },
            makeQuadBuffer: { device, range, vertices in
                bufferCallCount += 1
                return system.makeQuadBuffer(
                    device,
                    range,
                    vertices
                )
            }
        )

        let result = IRMetalRendererResources.make(
            device: device,
            dependencies: dependencies
        )

        guard case let .failure(failure) = result else {
            return XCTFail("Expected pipeline failure")
        }
        XCTAssertEqual(failure, .pipeline(.rgbMesh))
        XCTAssertEqual(bufferCallCount, 0)
    }

    func testEveryPipelineFailureMapsToItsTypedKind() throws {
        let device = try makeDevice()
        let system = ResourceDependencies.system

        for failedKind in IRMetalRendererPipelineKind.allCases {
            let dependencies = makeDependencies(
                makePipelineState: {
                    device,
                    kind,
                    descriptor in
                    guard kind != failedKind else {
                        return nil
                    }
                    return system.makePipelineState(
                        device,
                        kind,
                        descriptor
                    )
                }
            )

            let result = IRMetalRendererResources.make(
                device: device,
                dependencies: dependencies
            )

            guard case let .failure(failure) = result else {
                XCTFail(
                    "Expected failure for \(failedKind.rawValue)"
                )
                continue
            }
            XCTAssertEqual(failure, .pipeline(failedKind))
        }
    }

    func testQuadBufferFailureReportsExactRangeWithoutPublication()
        throws {
        let device = try makeDevice()
        let system = ResourceDependencies.system
        var attemptedRanges:
            [IRMetalRenderer.QuadTextureRange] = []
        let dependencies = makeDependencies(
            makeQuadBuffer: { device, range, vertices in
                attemptedRanges.append(range)
                guard range != .left else {
                    return nil
                }
                return system.makeQuadBuffer(
                    device,
                    range,
                    vertices
                )
            }
        )

        let result = IRMetalRendererResources.make(
            device: device,
            dependencies: dependencies
        )

        guard case let .failure(failure) = result else {
            return XCTFail("Expected quad-buffer failure")
        }
        XCTAssertEqual(failure, .quadBuffer(.left))
        XCTAssertEqual(attemptedRanges, [.full, .left])
    }

    func testEveryQuadBufferFailureMapsToItsTypedRange() throws {
        let device = try makeDevice()
        let system = ResourceDependencies.system

        for failedRange
            in IRMetalRenderer.QuadTextureRange.allCases {
            let dependencies = makeDependencies(
                makeQuadBuffer: {
                    device,
                    range,
                    vertices in
                    guard range != failedRange else {
                        return nil
                    }
                    return system.makeQuadBuffer(
                        device,
                        range,
                        vertices
                    )
                }
            )

            let result = IRMetalRendererResources.make(
                device: device,
                dependencies: dependencies
            )

            guard case let .failure(failure) = result else {
                XCTFail("Expected failure for \(failedRange)")
                continue
            }
            XCTAssertEqual(failure, .quadBuffer(failedRange))
        }
    }

    func testRendererFactoryUsesCallerProvidedCommandQueue() throws {
        let device = try makeDevice()
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())

        let result = IRMetalRenderer.make(
            device: device,
            commandQueue: commandQueue
        )

        guard case let .success(renderer) = result else {
            return XCTFail("Expected complete renderer")
        }
        XCTAssertTrue(renderer.commandQueue === commandQueue)
        XCTAssertEqual(renderer.resources.diagnostics.pipelineCount, 10)
        XCTAssertEqual(renderer.resources.diagnostics.quadBufferCount, 3)
    }

    func testRendererFactoryDoesNotPublishFailedResources() throws {
        let device = try makeDevice()
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let dependencies = makeDependencies(
            makePipelineState: { _, _, _ in nil }
        )

        let result = IRMetalRenderer.make(
            device: device,
            commandQueue: commandQueue,
            dependencies: dependencies
        )

        guard case let .failure(failure) = result else {
            return XCTFail("Expected renderer construction failure")
        }
        XCTAssertEqual(failure, .pipeline(.nv12))
    }
}
