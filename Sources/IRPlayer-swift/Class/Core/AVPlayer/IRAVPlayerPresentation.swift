import AVFoundation
import UIKit

// MARK: - Resource-backed values

extension IRAVPlayer {
    func reloadVolume() {
        guard let abstractPlayer else { return }
        let volume = IRPlayerVolume.normalizedFloat(
            from: abstractPlayer.volume
        )
        session.withResources(default: ()) {
            $0.player.volume = volume
        }
    }

    func reloadPlayableTime() {
        let value = session.withResources(
            default: Optional<TimeInterval>.none
        ) { resources -> TimeInterval? in
            guard resources.item.status == .readyToPlay,
                  let range =
                    resources.item.loadedTimeRanges.first?.timeRangeValue
            else {
                return nil
            }
            return Self.playableEndTime(
                start: Self.finiteSeconds(from: range.start),
                duration: Self.finiteSeconds(from: range.duration),
                totalDuration: Self.finiteSeconds(
                    from: resources.item.duration
                )
            )
        }
        playableTime = value ?? 0
    }

    var presentationSize: CGSize {
        session.withResources(default: .zero) {
            $0.item.presentationSize
        }
    }

    func snapshotAtCurrentTime() -> IRPLFImage? {
        guard abstractPlayer?.videoType == .normal else { return nil }
        return session.withResources(default: nil) { resources in
            let imageGenerator = AVAssetImageGenerator(
                asset: resources.asset
            )
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero

            do {
                let cgImage = try imageGenerator.copyCGImage(
                    at: resources.item.currentTime(),
                    actualTime: nil
                )
                return IRPLFImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }
    }

    func pixelBufferAtCurrentTime() -> CVPixelBuffer? {
        guard let token = session.currentToken else {
            return nil
        }
        return pixelBufferAtCurrentTime(for: token)
    }

    func pixelBufferAtCurrentTime(
        for token: IRAVPlayerSession.Token
    ) -> CVPixelBuffer? {
        guard !seeking else { return nil }
        let result = session.withResources(
            default:
                (
                    pixelBuffer: Optional<CVPixelBuffer>.none,
                    rebuildToken:
                        Optional<IRAVPlayerSession.Token>.none
                )
        ) { resources in
            guard resources.token == token,
                  let output = resources.output,
                  output.hasNewPixelBuffer(
                    forItemTime: resources.item.currentTime()
                  ) else {
                return (nil, nil)
            }
            guard let pixelBuffer = output.copyPixelBuffer(
                forItemTime: resources.item.currentTime(),
                itemTimeForDisplay: nil
            ) else {
                return (nil, resources.token)
            }
            return (pixelBuffer, nil)
        }

        if let rebuildToken = result.rebuildToken {
            session.rebuildVideoOutput(for: rebuildToken)
        }
        return result.pixelBuffer
    }

    func trySetupOutput() {
        let readyLongEnough =
            readyToPlayTime > 10 &&
            Date().timeIntervalSince1970 - readyToPlayTime > 0.3
        guard readyLongEnough,
              let token = session.withResources(
                default: Optional<IRAVPlayerSession.Token>.none,
                { resources in
                    resources.item.status == .readyToPlay
                        ? resources.token
                        : nil
                }
              ) else {
            return
        }
        session.rebuildVideoOutput(for: token)
    }
}

// MARK: - Presentation loop

extension IRAVPlayer {
    func handlePresentationTick(
        _ tick: IRAVPlayerPresentationLoop.Tick
    ) {
        guard abstractPlayer?.videoType == .vr,
              presentationLoop.isCurrent(tick),
              session.isCurrent(tick.sessionToken),
              let pixelBuffer =
                pixelBufferAtCurrentTime(
                    for: tick.sessionToken
                ),
              presentationLoop.isCurrent(tick),
              session.isCurrent(tick.sessionToken)
        else {
            return
        }
        let videoFrame = IRFFCVYUVVideoFrame(pixelBuffer: pixelBuffer)
        videoFrame.position = -1
        videoFrame.duration = -1
        abstractPlayer?.displayView?.render(videoFrame)
    }
}
