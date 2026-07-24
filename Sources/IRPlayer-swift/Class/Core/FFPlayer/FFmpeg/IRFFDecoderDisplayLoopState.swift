//
//  IRFFDecoderDisplayLoopState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import Foundation

enum IRFFDecoderDisplayLoopState {

    enum Action: Equatable {
        case quit
        case idleSleep(interval: TimeInterval, replayCurrentFrame: Bool)
        case finish
        case waitForAudio(interval: TimeInterval)
        case sleepAfterFrame(interval: TimeInterval)
    }

    static func exitAction(closed: Bool, hasError: Bool) -> Action? {
        return closed || hasError ? .quit : nil
    }

    static func idleAction(seeking: Bool,
                           buffering: Bool,
                           paused: Bool,
                           hasCurrentFrame: Bool) -> Action? {
        guard let interval = IRFFDecoder.displayIdleSleepInterval(
            seeking: seeking,
            buffering: buffering,
            paused: paused,
            hasCurrentFrame: hasCurrentFrame
        ) else {
            return nil
        }
        return .idleSleep(
            interval: interval,
            replayCurrentFrame: paused && !seeking && !buffering && hasCurrentFrame
        )
    }

    static func finishAction(endOfFile: Bool, videoDecoderEmpty: Bool) -> Action? {
        return IRFFDecoder.shouldFinishDisplay(
            endOfFile: endOfFile,
            videoDecoderEmpty: videoDecoderEmpty
        ) ? .finish : nil
    }

    static func audioSyncAction(currentFramePosition: TimeInterval?,
                                currentFrameDuration: TimeInterval?,
                                audioTimeClock: TimeInterval,
                                fps: TimeInterval) -> Action? {
        guard let currentFramePosition,
              let currentFrameDuration,
              let interval = IRFFDecoder.audioSyncedVideoSleepDuration(
                  framePosition: currentFramePosition,
                  frameDuration: currentFrameDuration,
                  audioTimeClock: audioTimeClock,
                  fps: fps
              ) else {
            return nil
        }
        return .waitForAudio(interval: interval)
    }

    static func shouldAcceptFrame(currentPosition: TimeInterval?,
                                  nextPosition: TimeInterval?) -> Bool {
        return IRFFDecoder.shouldAcceptVideoFrame(
            currentPosition: currentPosition,
            nextPosition: nextPosition
        )
    }

    static func standaloneSleepAction(frameDuration: TimeInterval, fps: TimeInterval) -> Action? {
        guard let interval = IRFFDecoder.standaloneVideoSleepDuration(
            frameDuration: frameDuration,
            fps: fps
        ) else {
            return nil
        }
        return .sleepAfterFrame(interval: interval)
    }
}
