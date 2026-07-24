//
//  IRMetalDistortionTargetSessionTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/7/24.
//

import Metal
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

private final class IRMetalTargetIdentityRecorder:
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedIdentities: [ObjectIdentifier] = []

    var identities: [ObjectIdentifier] {
        lock.lock()
        defer { lock.unlock() }
        return storedIdentities
    }

    func append(_ identity: ObjectIdentifier) {
        lock.lock()
        storedIdentities.append(identity)
        lock.unlock()
    }
}

final class IRMetalDistortionTargetSessionTests: XCTestCase {
    private func makeDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        return device
    }

    func testInitialDiagnosticsDescribeEmptyOpenOwner() throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )

        XCTAssertEqual(
            session.diagnostics,
            .init(
                phase: .idle,
                generation: 0,
                requestCount: 0,
                creationCount: 0,
                reuseCount: 0,
                failureCount: 0,
                resetCount: 0,
                rejectedOperationCount: 0,
                pixelWidth: 0,
                pixelHeight: 0,
                hasTarget: false
            )
        )
        XCTAssertNil(session.targetSnapshot)
    }

    func testEquivalentCanonicalSizesReuseOneTarget() throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )

        let first = try XCTUnwrap(
            session.target(
                for: CGSize(width: 10.1, height: 20.1)
            )
        )
        let second = try XCTUnwrap(
            session.target(
                for: CGSize(width: 10.9, height: 20.9)
            )
        )

        XCTAssertTrue(first === second)
        XCTAssertEqual(session.diagnostics.phase, .ready)
        XCTAssertEqual(session.diagnostics.generation, 1)
        XCTAssertEqual(session.diagnostics.creationCount, 1)
        XCTAssertEqual(session.diagnostics.reuseCount, 1)
        XCTAssertEqual(session.diagnostics.pixelWidth, 10)
        XCTAssertEqual(session.diagnostics.pixelHeight, 20)
    }

    func testChangedPixelSizePublishesCompleteReplacement() throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )
        let first = try XCTUnwrap(
            session.target(for: CGSize(width: 10, height: 20))
        )

        let second = try XCTUnwrap(
            session.target(for: CGSize(width: 11, height: 20))
        )

        XCTAssertFalse(first === second)
        XCTAssertTrue(session.targetSnapshot === second)
        XCTAssertEqual(session.diagnostics.generation, 2)
        XCTAssertEqual(session.diagnostics.creationCount, 2)
        XCTAssertEqual(session.diagnostics.pixelWidth, 11)
    }

    func testTargetDescriptorHasExactRenderAndReadContract()
        throws {
        let device = try makeDevice()
        var observedPixelFormat: MTLPixelFormat?
        var observedUsage: MTLTextureUsage?
        var observedWidth = 0
        var observedHeight = 0
        let dependencies = IRMetalDistortionTargetDependencies(
            makeTexture: { device, descriptor in
                observedPixelFormat = descriptor.pixelFormat
                observedUsage = descriptor.usage
                observedWidth = descriptor.width
                observedHeight = descriptor.height
                return device.makeTexture(descriptor: descriptor)
            }
        )
        let session = IRMetalDistortionTargetSession(
            device: device,
            dependencies: dependencies
        )

        XCTAssertNotNil(
            session.target(
                for: CGSize(width: 7.9, height: 5.4)
            )
        )

        XCTAssertEqual(observedPixelFormat, .bgra8Unorm)
        XCTAssertEqual(
            observedUsage,
            [.renderTarget, .shaderRead]
        )
        XCTAssertEqual(observedWidth, 7)
        XCTAssertEqual(observedHeight, 5)
    }

    func testInitialAllocationFailureRemainsIdle() throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice(),
            dependencies: .init(
                makeTexture: { _, _ in nil }
            )
        )

        XCTAssertNil(
            session.target(for: CGSize(width: 4, height: 4))
        )

        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertEqual(session.diagnostics.generation, 0)
        XCTAssertEqual(session.diagnostics.creationCount, 0)
        XCTAssertEqual(session.diagnostics.failureCount, 1)
        XCTAssertFalse(session.diagnostics.hasTarget)
    }

    func testAllocationFailurePreservesPriorCompleteTarget() throws {
        let device = try makeDevice()
        let dependencies = IRMetalDistortionTargetDependencies(
            makeTexture: { device, descriptor in
                guard descriptor.width == 4 else {
                    return nil
                }
                return device.makeTexture(descriptor: descriptor)
            }
        )
        let session = IRMetalDistortionTargetSession(
            device: device,
            dependencies: dependencies
        )
        let first = try XCTUnwrap(
            session.target(for: CGSize(width: 4, height: 4))
        )

        XCTAssertNil(
            session.target(for: CGSize(width: 5, height: 4))
        )

        XCTAssertTrue(session.targetSnapshot === first)
        XCTAssertEqual(session.diagnostics.phase, .ready)
        XCTAssertEqual(session.diagnostics.generation, 1)
        XCTAssertEqual(session.diagnostics.failureCount, 1)
        XCTAssertEqual(session.diagnostics.pixelWidth, 4)
        XCTAssertEqual(session.diagnostics.pixelHeight, 4)
    }

    func testInvalidRequestPreservesPriorCompleteTarget() throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )
        let first = try XCTUnwrap(
            session.target(for: CGSize(width: 4, height: 4))
        )

        XCTAssertNil(
            session.target(
                for: CGSize(width: CGFloat.nan, height: 4)
            )
        )

        XCTAssertTrue(session.targetSnapshot === first)
        XCTAssertEqual(session.diagnostics.failureCount, 1)
        XCTAssertEqual(session.diagnostics.creationCount, 1)
    }

    func testResetClearsTargetAndAllowsNewGeneration() throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )
        let first = try XCTUnwrap(
            session.target(for: CGSize(width: 4, height: 4))
        )

        session.reset()
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertNil(session.targetSnapshot)

        let second = try XCTUnwrap(
            session.target(for: CGSize(width: 4, height: 4))
        )
        XCTAssertFalse(first === second)
        XCTAssertEqual(session.diagnostics.generation, 2)
        XCTAssertEqual(session.diagnostics.resetCount, 1)
    }

    func testCloseIsTerminalAndRejectsResetAndTargetRequests()
        throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )
        XCTAssertNotNil(
            session.target(for: CGSize(width: 4, height: 4))
        )

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        session.reset()
        XCTAssertNil(
            session.target(for: CGSize(width: 4, height: 4))
        )

        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.diagnostics.hasTarget)
        XCTAssertEqual(
            session.diagnostics.rejectedOperationCount,
            2
        )
    }

    func testConcurrentEquivalentRequestsPublishOneGeneration()
        throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )
        let identities = IRMetalTargetIdentityRecorder()

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard let texture = session.target(
                for: CGSize(width: 8.75, height: 6.5)
            ) else {
                return
            }
            identities.append(ObjectIdentifier(texture))
        }

        XCTAssertEqual(identities.identities.count, 100)
        XCTAssertEqual(Set(identities.identities).count, 1)
        XCTAssertEqual(session.diagnostics.requestCount, 100)
        XCTAssertEqual(session.diagnostics.creationCount, 1)
        XCTAssertEqual(session.diagnostics.reuseCount, 99)
    }

    func testConcurrentRequestsAndCloseEndTerminallyClosed()
        throws {
        let session = IRMetalDistortionTargetSession(
            device: try makeDevice()
        )

        DispatchQueue.concurrentPerform(iterations: 101) {
            index in
            if index == 100 {
                _ = session.close()
            } else {
                _ = session.target(
                    for: CGSize(width: 8, height: 6)
                )
            }
        }

        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertFalse(session.diagnostics.hasTarget)
        XCTAssertNil(
            session.target(for: CGSize(width: 8, height: 6))
        )
    }

    func testDeinitReleasesSession() throws {
        let device = try makeDevice()
        weak var weakSession: IRMetalDistortionTargetSession?

        autoreleasepool {
            let session = IRMetalDistortionTargetSession(
                device: device
            )
            weakSession = session
            XCTAssertNotNil(
                session.target(for: CGSize(width: 4, height: 4))
            )
        }

        XCTAssertNil(weakSession)
    }

    func testTextureSizeRejectsSubpixelAndIntegerOverflow() {
        XCTAssertNil(
            IRMetalDistortionTargetSession.textureSize(
                from: CGSize(width: 0.5, height: 1)
            )
        )
        XCTAssertNil(
            IRMetalDistortionTargetSession.textureSize(
                from: CGSize(
                    width: CGFloat(Int.max),
                    height: 1
                )
            )
        )
    }

    func testScissorRectsRequireTwoHorizontalPixels() {
        XCTAssertNil(
            IRMetalDistortionTargetSession.scissorRects(
                drawableSize: CGSize(width: 1, height: 4)
            )
        )
    }
}
