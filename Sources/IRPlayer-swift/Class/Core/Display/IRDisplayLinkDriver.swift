//
//  IRDisplayLinkDriver.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import UIKit

enum IRDisplayLinkPhase: Equatable, Sendable {
    case uninstalled
    case idle
    case active
    case closed
}

struct IRDisplayLinkSnapshot: Equatable, Sendable {
    let phase: IRDisplayLinkPhase
    let scheduledMode: String?
}

protocol IRDisplayLinkDriving: AnyObject {
    var snapshot: IRDisplayLinkSnapshot { get }

    @discardableResult
    func install(
        handler: @escaping (TimeInterval) -> Void
    ) -> Bool

    @discardableResult
    func setActive(_ isActive: Bool) -> Bool

    @discardableResult
    func close() -> Bool
}

private final class IRDisplayLinkProxy:
    NSObject
{
    weak var driver: IRSystemDisplayLinkDriver?

    init(driver: IRSystemDisplayLinkDriver) {
        self.driver = driver
    }

    @objc func tick(_ sender: CADisplayLink) {
        driver?.emit(timestamp: sender.timestamp)
    }
}

final class IRSystemDisplayLinkDriver:
    IRDisplayLinkDriving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var phase:
        IRDisplayLinkPhase = .uninstalled
    private var scheduledMode: String?
    private var displayLink: CADisplayLink?
    private var proxy: IRDisplayLinkProxy?
    private var handler: ((TimeInterval) -> Void)?

    var snapshot: IRDisplayLinkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return IRDisplayLinkSnapshot(
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
        let proxy = IRDisplayLinkProxy(
            driver: self
        )
        let displayLink = CADisplayLink(
            target: proxy,
            selector:
                #selector(
                    IRDisplayLinkProxy.tick(_:)
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
