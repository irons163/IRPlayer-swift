//
//  IRSmoothScrollDisplayLinkDriver.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import UIKit

enum IRSmoothScrollDisplayLinkPhase: Equatable {
    case uninstalled
    case idle
    case active
    case closed
}

struct IRSmoothScrollDisplayLinkSnapshot: Equatable {
    let phase: IRSmoothScrollDisplayLinkPhase
    let scheduledMode: String?
}

protocol IRSmoothScrollDisplayLinkDriving: AnyObject {
    var snapshot: IRSmoothScrollDisplayLinkSnapshot { get }

    @discardableResult
    func install(
        handler: @escaping (TimeInterval) -> Void
    ) -> Bool

    @discardableResult
    func setActive(_ isActive: Bool) -> Bool

    @discardableResult
    func close() -> Bool
}

private final class IRSmoothScrollDisplayLinkProxy:
    NSObject
{
    weak var driver: IRSystemSmoothScrollDisplayLinkDriver?

    init(driver: IRSystemSmoothScrollDisplayLinkDriver) {
        self.driver = driver
    }

    @objc func tick(_ sender: CADisplayLink) {
        driver?.emit(timestamp: sender.timestamp)
    }
}

final class IRSystemSmoothScrollDisplayLinkDriver:
    IRSmoothScrollDisplayLinkDriving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var phase:
        IRSmoothScrollDisplayLinkPhase = .uninstalled
    private var scheduledMode: String?
    private var displayLink: CADisplayLink?
    private var proxy: IRSmoothScrollDisplayLinkProxy?
    private var handler: ((TimeInterval) -> Void)?

    var snapshot: IRSmoothScrollDisplayLinkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return IRSmoothScrollDisplayLinkSnapshot(
            phase: phase,
            scheduledMode: scheduledMode
        )
    }

    @discardableResult
    func install(
        handler: @escaping (TimeInterval) -> Void
    ) -> Bool {
        guard Thread.isMainThread else {
            return false
        }

        lock.lock()
        guard phase == .uninstalled else {
            lock.unlock()
            return false
        }
        let proxy = IRSmoothScrollDisplayLinkProxy(
            driver: self
        )
        let displayLink = CADisplayLink(
            target: proxy,
            selector:
                #selector(
                    IRSmoothScrollDisplayLinkProxy.tick(_:)
                )
        )
        displayLink.isPaused = true
        self.handler = handler
        self.proxy = proxy
        self.displayLink = displayLink
        scheduledMode = RunLoop.Mode.common.rawValue
        phase = .idle
        lock.unlock()

        displayLink.add(to: .main, forMode: .common)
        return true
    }

    @discardableResult
    func setActive(_ isActive: Bool) -> Bool {
        guard Thread.isMainThread else {
            return false
        }

        lock.lock()
        guard phase == .idle || phase == .active,
              let displayLink else {
            lock.unlock()
            return false
        }
        phase = isActive ? .active : .idle
        lock.unlock()

        displayLink.isPaused = !isActive
        return true
    }

    @discardableResult
    func close() -> Bool {
        let displayLink: CADisplayLink?
        lock.lock()
        guard phase != .closed else {
            lock.unlock()
            return false
        }
        phase = .closed
        handler = nil
        scheduledMode = nil
        displayLink = self.displayLink
        self.displayLink = nil
        proxy = nil
        lock.unlock()

        guard let displayLink else {
            return true
        }
        if Thread.isMainThread {
            displayLink.invalidate()
        } else {
            DispatchQueue.main.async {
                displayLink.invalidate()
            }
        }
        return true
    }

    func emit(timestamp: TimeInterval) {
        let handler: ((TimeInterval) -> Void)?
        lock.lock()
        handler = phase == .active
            ? self.handler
            : nil
        lock.unlock()
        handler?(timestamp)
    }

    deinit {
        _ = close()
    }
}
