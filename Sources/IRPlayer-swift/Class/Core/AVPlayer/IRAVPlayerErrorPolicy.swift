import AVFoundation

enum IRAVPlayerErrorPolicy {

    static func playbackErrorInfo(playerItem: AVPlayerItem?, player: AVPlayer?) -> IRError {
        let errorInfo = IRError()

        if let playerItemError = playerItem?.error {
            errorInfo.error = playerItemError as NSError

            if let extendedLogData = playerItem?.errorLog()?.extendedLogData(), extendedLogData.count > 0 {
                errorInfo.extendedLogData = extendedLogData
                errorInfo.extendedLogDataStringEncoding = String.Encoding(rawValue: playerItem?.errorLog()?.extendedLogDataStringEncoding ?? 0).rawValue
            }

            if let errorEvents = playerItem?.errorLog()?.events {
                errorInfo.errorEvents = errorEvents.map { event in
                    let errorEvent = IRErrorEvent()
                    errorEvent.date = event.date
                    errorEvent.URI = event.uri
                    errorEvent.serverAddress = event.serverAddress
                    errorEvent.playbackSessionID = event.playbackSessionID
                    errorEvent.errorStatusCode = event.errorStatusCode
                    errorEvent.errorDomain = event.errorDomain
                    errorEvent.errorComment = event.errorComment
                    return errorEvent
                }
            }
        } else if let playerError = player?.error {
            errorInfo.error = playerError as NSError
        } else {
            errorInfo.error = NSError(domain: "AVPlayer playback error", code: -1, userInfo: nil)
        }

        return errorInfo
    }
}
