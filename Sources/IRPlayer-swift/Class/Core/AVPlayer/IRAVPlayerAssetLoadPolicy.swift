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

enum IRAVPlayerResourceLoaderPolicy {

    static func redirectRequest(for request: URLRequest, headers: [String: String]?) -> URLRequest? {
        guard let headers = headers, !headers.isEmpty else {
            return nil
        }

        guard request.url?.scheme?.lowercased() == "https" else {
            return nil
        }

        var redirectRequest = request
        headers.forEach { key, value in
            redirectRequest.setValue(value, forHTTPHeaderField: key)
        }
        return redirectRequest
    }
}
