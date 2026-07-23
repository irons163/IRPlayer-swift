import AVFoundation
import Foundation
import QuartzCore

struct IRGLAVPlayerLayerDependencies {
    let makeLayer: () -> AVPlayerLayer

    static var system: IRGLAVPlayerLayerDependencies {
        IRGLAVPlayerLayerDependencies(makeLayer: AVPlayerLayer.init)
    }
}

final class IRGLAVPlayerLayerSession: @unchecked Sendable {
    struct Diagnostics {
        let isClosed: Bool
        let hasLayer: Bool
        let hasPlayer: Bool
        let layerGeneration: UInt64
        let attachmentCount: Int
        let layoutCount: Int
        let detachCount: Int
    }

    private let dependencies: IRGLAVPlayerLayerDependencies

    private var playerLayer: AVPlayerLayer?
    private var closed = false
    private var layerGeneration: UInt64 = 0
    private var attachmentCount = 0
    private var layoutCount = 0
    private var detachCount = 0

    init(dependencies: IRGLAVPlayerLayerDependencies = .system) {
        self.dependencies = dependencies
    }

    var diagnostics: Diagnostics {
        IRMainThreadExecutor.sync {
            Diagnostics(
                isClosed: closed,
                hasLayer: playerLayer != nil,
                hasPlayer: playerLayer?.player != nil,
                layerGeneration: layerGeneration,
                attachmentCount: attachmentCount,
                layoutCount: layoutCount,
                detachCount: detachCount
            )
        }
    }

    var attachedPlayer: AVPlayer? {
        IRMainThreadExecutor.sync { playerLayer?.player }
    }

    var layerSnapshot: AVPlayerLayer? {
        IRMainThreadExecutor.sync { playerLayer }
    }

    @discardableResult
    func setPlayer(
        _ player: AVPlayer?,
        hostLayer: CALayer,
        bounds: CGRect,
        gravity: AVLayerVideoGravity
    ) -> Bool {
        IRMainThreadExecutor.sync {
            guard !closed else { return false }
            guard let player else {
                detachLocked()
                return true
            }

            let layer: AVPlayerLayer
            if let playerLayer {
                layer = playerLayer
            } else {
                layer = dependencies.makeLayer()
                playerLayer = layer
                layerGeneration &+= 1
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.player = player
            layer.frame = bounds
            layer.videoGravity = gravity
            if layer.superlayer !== hostLayer {
                layer.removeFromSuperlayer()
                hostLayer.addSublayer(layer)
            }
            CATransaction.commit()
            attachmentCount += 1
            return true
        }
    }

    func layout(bounds: CGRect) {
        IRMainThreadExecutor.sync {
            guard !closed, let playerLayer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
            layoutCount += 1
        }
    }

    func updateGravity(_ gravity: AVLayerVideoGravity) {
        IRMainThreadExecutor.sync {
            guard !closed, let playerLayer else { return }
            playerLayer.videoGravity = gravity
        }
    }

    func reset() {
        IRMainThreadExecutor.sync {
            guard !closed else { return }
            detachLocked()
        }
    }

    @discardableResult
    func close() -> Bool {
        IRMainThreadExecutor.sync {
            guard !closed else { return false }
            closed = true
            detachLocked()
            return true
        }
    }

    private func detachLocked() {
        guard let playerLayer else { return }
        playerLayer.player = nil
        playerLayer.removeFromSuperlayer()
        self.playerLayer = nil
        detachCount += 1
    }
}
