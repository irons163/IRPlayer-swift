//
//  IRMetalCommandResources.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import Metal

enum IRMetalCommandResourceState: Equatable {
    case collecting
    case submitted
    case cancelled
}

struct IRMetalCommandResourceDiagnostics: Equatable {
    let state: IRMetalCommandResourceState
    let cachedFrameCount: Int
    let additionalResourceCount: Int
}

final class IRMetalCommandResources:
    @unchecked Sendable
{
    typealias CompletionRegistrar =
        (@escaping @Sendable () -> Void) -> Void

    private final class CompletionResources:
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var resources: [AnyObject]
        private var didComplete = false

        init(resources: [AnyObject]) {
            self.resources = resources
        }

        @discardableResult
        func complete() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return false }
            didComplete = true
            resources.removeAll(keepingCapacity: false)
            return true
        }
    }

    private let lock = NSLock()
    private var state: IRMetalCommandResourceState =
        .collecting
    private var frameGenerations: [
        ObjectIdentifier: IRMetalFrameTextureGeneration
    ] = [:]
    private var additionalResources: [AnyObject] = []

    deinit {
        cancel()
    }

    var diagnostics: IRMetalCommandResourceDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return IRMetalCommandResourceDiagnostics(
            state: state,
            cachedFrameCount: frameGenerations.count,
            additionalResourceCount: additionalResources.count
        )
    }

    func frameTextureGeneration(
        for frame: IRFFVideoFrame,
        make: () -> IRMetalFrameTextureGeneration?
    ) -> IRMetalFrameTextureGeneration? {
        lock.lock()
        defer { lock.unlock() }

        guard state == .collecting else {
            return nil
        }

        let key = ObjectIdentifier(frame)
        if let generation = frameGenerations[key] {
            return generation
        }
        guard let generation = make() else {
            return nil
        }
        frameGenerations[key] = generation
        return generation
    }

    @discardableResult
    func retain(_ resource: AnyObject) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .collecting else {
            return false
        }
        additionalResources.append(resource)
        return true
    }

    @discardableResult
    func submit(
        registerCompletion: CompletionRegistrar
    ) -> Bool {
        submit(
            registerCompletion: registerCompletion,
            completion: {}
        )
    }

    @discardableResult
    func submit(
        registerCompletion: CompletionRegistrar,
        completion: @escaping @Sendable () -> Void
    ) -> Bool {
        let completionResources: CompletionResources

        lock.lock()
        guard state == .collecting else {
            lock.unlock()
            return false
        }
        state = .submitted
        let frameResources: [AnyObject] =
            frameGenerations.values.map { $0 }
        completionResources = CompletionResources(
            resources:
                frameResources
                + additionalResources
        )
        frameGenerations.removeAll(keepingCapacity: false)
        additionalResources.removeAll(keepingCapacity: false)
        lock.unlock()

        registerCompletion {
            guard completionResources.complete() else {
                return
            }
            completion()
        }
        return true
    }

    @discardableResult
    func submit(to commandBuffer: MTLCommandBuffer) -> Bool {
        submit(to: commandBuffer, completion: {})
    }

    @discardableResult
    func submit(
        to commandBuffer: MTLCommandBuffer,
        completion: @escaping @Sendable () -> Void
    ) -> Bool {
        submit(
            registerCompletion: { registeredCompletion in
                commandBuffer.addCompletedHandler { _ in
                    registeredCompletion()
                }
            },
            completion: completion
        )
    }

    @discardableResult
    func cancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .collecting else {
            return false
        }
        state = .cancelled
        frameGenerations.removeAll(keepingCapacity: false)
        additionalResources.removeAll(keepingCapacity: false)
        return true
    }
}
