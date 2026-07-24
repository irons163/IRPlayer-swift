import AVFoundation
import Foundation

// MARK: - Session events and failures

extension IRAVPlayer {
    struct ErrorLogEventSnapshot {
        let date: Date?
        let URI: String?
        let serverAddress: String?
        let playbackSessionID: String?
        let errorStatusCode: Int
        let errorDomain: String
        let errorComment: String?
    }

    private func handleItemEvent(
        token: IRAVPlayerSession.Token,
        item: AVPlayerItem,
        event: IRAVPlayerSession.ItemEvent
    ) {
        guard session.isCurrent(token, item: item) else { return }

        switch event {
        case .statusChanged:
            handleItemStatus(item.status)

        case .playbackBufferEmptyChanged:
            if item.isPlaybackBufferEmpty {
                setPlayIfNeeded()
            }

        case .loadedTimeRangesChanged:
            reloadPlayableTime()
            guard let abstractPlayer else { return }
            let interval = playableTime - progress
            let residue = duration - progress
            if interval > abstractPlayer.playableBufferInterval {
                playIfNeeded()
            } else if interval < 0.3 && residue > 1.5 {
                setPlayIfNeeded()
            }

        case .didPlayToEnd:
            state = .finished
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        switch Self.itemStatusDecision(
            status: status,
            currentState: state
        ) {
        case .buffer:
            state = .buffering

        case .markReady:
            setupTrackInfo()
            readyToPlayTime = Date().timeIntervalSince1970
            state = .readyToPlay

        case .playIfNeeded:
            setupTrackInfo()
            readyToPlayTime = Date().timeIntervalSince1970
            playIfNeeded()

        case .fail:
            failPlayback(with: playbackErrorInfo())

        case .failUnknown:
            let errorInfo = IRError()
            errorInfo.error = NSError(
                domain: "AVPlayer item status unknown",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "AVPlayerItem reported an unknown status."
                ]
            )
            failPlayback(with: errorInfo)

        case .ignore:
            break
        }
    }

    private func handlePeriodicTime(
        token: IRAVPlayerSession.Token,
        time: CMTime
    ) {
        guard state == .playing,
              session.isCurrent(token),
              let abstractPlayer else {
            return
        }
        abstractPlayer.playbackBackendDidUpdateProgress(
            current: Self.finiteSeconds(from: time),
            total: duration
        )
    }

    func avAssetPrepareFailed(error: Error?) {
        readyToPlayTime = 0
        let errorInfo = IRError()
        if let error {
            errorInfo.error = error as NSError
        }
        failPlayback(with: errorInfo)
    }

    private func playbackErrorInfo() -> IRError {
        readyToPlayTime = 0
        return session.withResources(
            default: Self.playbackErrorInfo(
                playerItem: nil,
                player: nil
            )
        ) {
            Self.playbackErrorInfo(
                playerItem: $0.item,
                player: $0.player
            )
        }
    }

    static func playbackErrorInfo(
        playerItem: AVPlayerItem?,
        player: AVPlayer?
    ) -> IRError {
        let errorLog =
            playerItem?.error == nil
                ? nil
                : playerItem?.errorLog()
        return errorInfo(
            playerItemError: playerItem?.error as NSError?,
            playerError: player?.error as NSError?,
            extendedLogData: errorLog?.extendedLogData(),
            extendedLogDataStringEncoding:
                String.Encoding(
                    rawValue:
                        errorLog?
                            .extendedLogDataStringEncoding ?? 0
                ).rawValue,
            errorEvents: errorLog?.events.map {
                ErrorLogEventSnapshot(
                    date: $0.date,
                    URI: $0.uri,
                    serverAddress: $0.serverAddress,
                    playbackSessionID: $0.playbackSessionID,
                    errorStatusCode: $0.errorStatusCode,
                    errorDomain: $0.errorDomain,
                    errorComment: $0.errorComment
                )
            }
        )
    }

    static func errorInfo(
        playerItemError: NSError?,
        playerError: NSError?,
        extendedLogData: Data?,
        extendedLogDataStringEncoding: UInt,
        errorEvents: [ErrorLogEventSnapshot]?
    ) -> IRError {
        let errorInfo = IRError()

        if let playerItemError {
            errorInfo.error = playerItemError
            applyExtendedLogData(
                extendedLogData,
                stringEncoding:
                    extendedLogDataStringEncoding,
                to: errorInfo
            )
            errorInfo.errorEvents = errorEvents?.map {
                errorEvent(
                    date: $0.date,
                    URI: $0.URI,
                    serverAddress: $0.serverAddress,
                    playbackSessionID:
                        $0.playbackSessionID,
                    errorStatusCode:
                        $0.errorStatusCode,
                    errorDomain: $0.errorDomain,
                    errorComment: $0.errorComment
                )
            }
        } else if let playerError {
            errorInfo.error = playerError
        } else {
            errorInfo.error = NSError(
                domain: "AVPlayer playback error",
                code: -1,
                userInfo: nil
            )
        }

        return errorInfo
    }

    static func applyExtendedLogData(
        _ data: Data?,
        stringEncoding: UInt,
        to errorInfo: IRError
    ) {
        guard let data, !data.isEmpty else { return }
        errorInfo.extendedLogData = data
        errorInfo.extendedLogDataStringEncoding =
            stringEncoding
    }

    static func errorEvent(
        date: Date?,
        URI: String?,
        serverAddress: String?,
        playbackSessionID: String?,
        errorStatusCode: Int,
        errorDomain: String,
        errorComment: String?
    ) -> IRErrorEvent {
        let event = IRErrorEvent()
        event.date = date
        event.URI = URI
        event.serverAddress = serverAddress
        event.playbackSessionID = playbackSessionID
        event.errorStatusCode = errorStatusCode
        event.errorDomain = errorDomain
        event.errorComment = errorComment
        return event
    }

    private func failPlayback(with errorInfo: IRError) {
        _ = presentationLoop.deactivate()
        guard let abstractPlayer else {
            state = .failed
            return
        }
        abstractPlayer.error = errorInfo
        state = .failed
        abstractPlayer.playbackBackendDidFail(errorInfo)
    }
}

// MARK: - Activation and reset

extension IRAVPlayer {
    func tryReplaceVideo() {
        if session.currentToken == nil {
            replaceVideo()
        }
    }

    func replaceVideo() {
        replaceEmpty()
        guard let abstractPlayer,
              let contentURL = abstractPlayer.contentURL else {
            return
        }

        let automaticallyLoadedAssetKeys: [String]?
        switch abstractPlayer.videoType {
        case .normal:
            automaticallyLoadedAssetKeys = Self.AVAssetLoadKeys
        case .vr:
            automaticallyLoadedAssetKeys = nil
        case .fisheye, .pano, .custom:
            return
        }

        let asset = AVURLAsset(url: contentURL as URL)
        guard let token = activateSession(
            asset: asset,
            automaticallyLoadedAssetKeys: automaticallyLoadedAssetKeys,
            contentHeaders: abstractPlayer.contentHeaders
        ) else {
            return
        }
        reloadVolume()

        switch abstractPlayer.videoType {
        case .normal:
            _ = presentationLoop.deactivate()
            abstractPlayer.displayView?.rendererType = .AVPlayerLayer
            abstractPlayer.displayView?.setAVPlayer(avPlayer)

        case .vr:
            guard presentationLoop.activate(
                sessionToken: token
            ) != nil else {
                replaceEmpty()
                return
            }
            abstractPlayer.displayView?.setAVPlayer(nil)
            abstractPlayer.displayView?.rendererType =
                .AVPlayerPixelBufferVR
            loadVRAsset(asset, token: token)

        case .fisheye, .pano, .custom:
            break
        }
    }

    @discardableResult
    func activateSession(
        asset: AVURLAsset,
        automaticallyLoadedAssetKeys: [String]?,
        contentHeaders: [String: String]? = nil
    ) -> IRAVPlayerSession.Token? {
        session.activate(
            asset: asset,
            automaticallyLoadedAssetKeys:
                automaticallyLoadedAssetKeys,
            contentHeaders: contentHeaders,
            itemEventHandler: { [weak self] token, item, event in
                self?.handleItemEvent(
                    token: token,
                    item: item,
                    event: event
                )
            },
            periodicTimeHandler: { [weak self] token, time in
                self?.handlePeriodicTime(token: token, time: time)
            }
        )
    }

    private func loadVRAsset(
        _ asset: AVURLAsset,
        token: IRAVPlayerSession.Token
    ) {
        asset.loadValuesAsynchronously(forKeys: Self.AVAssetLoadKeys) {
            [weak self, weak asset] in
            DispatchQueue.main.async {
                guard let self,
                      let asset,
                      self.session.isCurrent(token, asset: asset) else {
                    return
                }

                var keyStatuses: [AVKeyValueStatus] = []
                var failureError: NSError?
                for loadKey in Self.AVAssetLoadKeys {
                    var error: NSError?
                    let status = asset.statusOfValue(
                        forKey: loadKey,
                        error: &error
                    )
                    keyStatuses.append(status)
                    if status == .failed, failureError == nil {
                        failureError = error
                    }
                }
                let trackStatus = asset.statusOfValue(
                    forKey: "tracks",
                    error: nil
                )
                switch Self.avAssetLoadDecision(
                    keyStatuses: keyStatuses,
                    trackStatus: trackStatus
                ) {
                case .fail:
                    self.avAssetPrepareFailed(error: failureError)
                case .setupOutput:
                    self.session.rebuildVideoOutput(for: token)
                case .ignore:
                    break
                }
            }
        }
    }

    func replaceEmpty() {
        _ = presentationLoop.deactivate()
        cancelPendingSeek()
        session.reset()
        abstractPlayer?.displayView?.setAVPlayer(nil)

        let shouldSendPlayableReset = playableTime == 0
        playableTime = 0
        if let abstractPlayer {
            if shouldSendPlayableReset {
                abstractPlayer.playbackBackendDidUpdatePlayableTime(
                    current: 0,
                    total: 0
                )
            }
            abstractPlayer.playbackBackendDidUpdateProgress(
                current: 0,
                total: 0
            )
        }

        cleanTrackInfo()
        state = .none
        needPlay = false
        readyToPlayTime = 0
        abstractPlayer?.displayView?.cleanEmptyBuffer()
    }
}
