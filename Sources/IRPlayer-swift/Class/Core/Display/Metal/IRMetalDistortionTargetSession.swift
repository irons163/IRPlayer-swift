//
//  IRMetalDistortionTargetSession.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import CoreGraphics
import Foundation
import Metal

enum IRMetalDistortionTargetPhase: Equatable {
    case idle
    case ready
    case closed
}

struct IRMetalDistortionTargetDiagnostics: Equatable {
    let phase: IRMetalDistortionTargetPhase
    let generation: UInt64
    let requestCount: Int
    let creationCount: Int
    let reuseCount: Int
    let failureCount: Int
    let resetCount: Int
    let rejectedOperationCount: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let hasTarget: Bool
}

struct IRMetalDistortionTargetDependencies {
    let makeTexture: (MTLDevice, MTLTextureDescriptor) -> MTLTexture?

    static var system: IRMetalDistortionTargetDependencies {
        IRMetalDistortionTargetDependencies(
            makeTexture: { device, descriptor in
                device.makeTexture(descriptor: descriptor)
            }
        )
    }
}

final class IRMetalDistortionTargetSession: @unchecked Sendable {
    private struct Generation {
        let width: Int
        let height: Int
        let texture: MTLTexture
    }

    private let device: MTLDevice
    private let dependencies: IRMetalDistortionTargetDependencies
    private let lock = NSLock()

    private var phase: IRMetalDistortionTargetPhase = .idle
    private var target: Generation?
    private var generation: UInt64 = 0
    private var requestCount = 0
    private var creationCount = 0
    private var reuseCount = 0
    private var failureCount = 0
    private var resetCount = 0
    private var rejectedOperationCount = 0

    init(
        device: MTLDevice,
        dependencies: IRMetalDistortionTargetDependencies = .system
    ) {
        self.device = device
        self.dependencies = dependencies
    }

    deinit {
        _ = close()
    }

    var diagnostics: IRMetalDistortionTargetDiagnostics {
        withLock {
            IRMetalDistortionTargetDiagnostics(
                phase: phase,
                generation: generation,
                requestCount: requestCount,
                creationCount: creationCount,
                reuseCount: reuseCount,
                failureCount: failureCount,
                resetCount: resetCount,
                rejectedOperationCount: rejectedOperationCount,
                pixelWidth: target?.width ?? 0,
                pixelHeight: target?.height ?? 0,
                hasTarget: target != nil
            )
        }
    }

    var targetSnapshot: MTLTexture? {
        withLock { target?.texture }
    }

    func target(for drawableSize: CGSize) -> MTLTexture? {
        withLock {
            guard phase != .closed else {
                rejectedOperationCount += 1
                return nil
            }
            requestCount += 1
            guard let size = Self.textureSize(from: drawableSize) else {
                failureCount += 1
                return nil
            }
            if let target,
               target.width == size.width,
               target.height == size.height {
                reuseCount += 1
                return target.texture
            }

            let descriptor =
                MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: size.width,
                    height: size.height,
                    mipmapped: false
                )
            descriptor.usage = [.renderTarget, .shaderRead]
            guard let texture = dependencies.makeTexture(
                device,
                descriptor
            ) else {
                failureCount += 1
                return nil
            }

            target = Generation(
                width: size.width,
                height: size.height,
                texture: texture
            )
            generation &+= 1
            creationCount += 1
            phase = .ready
            return texture
        }
    }

    func reset() {
        withLock {
            guard phase != .closed else {
                rejectedOperationCount += 1
                return
            }
            target = nil
            phase = .idle
            resetCount += 1
        }
    }

    @discardableResult
    func close() -> Bool {
        withLock {
            guard phase != .closed else {
                return false
            }
            target = nil
            phase = .closed
            return true
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    static func textureSize(
        from size: CGSize
    ) -> (width: Int, height: Int)? {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width < CGFloat(Int.max),
              size.height < CGFloat(Int.max) else {
            return nil
        }
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else {
            return nil
        }
        return (width, height)
    }

    static func scissorRects(
        drawableSize: CGSize
    ) -> (left: MTLScissorRect, right: MTLScissorRect)? {
        guard let textureSize = textureSize(from: drawableSize),
              textureSize.width >= 2 else {
            return nil
        }
        let leftWidth = textureSize.width / 2
        let rightWidth = textureSize.width - leftWidth
        return (
            MTLScissorRect(
                x: 0,
                y: 0,
                width: leftWidth,
                height: textureSize.height
            ),
            MTLScissorRect(
                x: leftWidth,
                y: 0,
                width: rightWidth,
                height: textureSize.height
            )
        )
    }
}
