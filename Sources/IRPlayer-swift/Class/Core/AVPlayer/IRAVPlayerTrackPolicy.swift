import AVFoundation

enum IRAVPlayerTrackPolicy {

    static func trackName(languageCode: String?, trackID: CMPersistentTrackID) -> String {
        guard let languageCode, !languageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Track \(trackID)"
        }
        return languageCode
    }

    static func mediaSelectionTrackID(from propertyList: Any?) -> Int? {
        guard let propertyList = propertyList as? [String: Any],
              let value = propertyList[IRAVPlayer.avMediaSelectionOptionTrackIDKey] else { return nil }

        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    static func defaultTrack(from tracks: [IRPlayerTrack], propertyList: Any?) -> IRPlayerTrack? {
        guard let trackID = mediaSelectionTrackID(from: propertyList) else {
            return tracks.first
        }
        return tracks.first { $0.index == trackID } ?? tracks.first
    }
}
