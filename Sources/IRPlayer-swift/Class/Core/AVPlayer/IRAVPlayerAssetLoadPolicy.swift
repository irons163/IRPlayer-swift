import AVFoundation

enum IRAVPlayerAssetLoadPolicy {

    static func decision(keyStatuses: [AVKeyValueStatus], trackStatus: AVKeyValueStatus?) -> IRAVPlayer.AVAssetLoadDecision {
        if keyStatuses.contains(.failed) {
            return .fail
        }
        if trackStatus == .loaded {
            return .setupOutput
        }
        return .ignore
    }
}
