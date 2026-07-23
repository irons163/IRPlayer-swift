import AVFoundation

// MARK: - Track information

extension IRAVPlayer {
    func setupTrackInfo() {
        guard !videoEnable, !audioEnable,
              let asset = session.withResources(
                default: Optional<AVURLAsset>.none,
                { $0.asset }
              ) else {
            return
        }

        var videoTracks: [IRPlayerTrack] = []
        var audioTracks: [IRPlayerTrack] = []
        asset.tracks.forEach { track in
            if track.mediaType == .video {
                videoEnable = true
                videoTracks.append(playerTrack(from: track))
            } else if track.mediaType == .audio {
                audioEnable = true
                audioTracks.append(playerTrack(from: track))
            }
        }

        self.videoTracks = videoTracks
        self.audioTracks = audioTracks
        setupDefaultTrack(
            for: .visual,
            from: videoTracks,
            asset: asset
        )
        setupDefaultTrack(
            for: .audible,
            from: audioTracks,
            asset: asset
        )
    }

    private func setupDefaultTrack(
        for characteristic: AVMediaCharacteristic,
        from tracks: [IRPlayerTrack],
        asset: AVURLAsset
    ) {
        guard let group = asset.mediaSelectionGroup(
            forMediaCharacteristic: characteristic
        ) else {
            return
        }
        let defaultTrack = Self.defaultTrack(
            from: tracks,
            propertyList: group.defaultOption?.propertyList
        )
        if characteristic == .visual {
            videoTrack = defaultTrack
        } else if characteristic == .audible {
            audioTrack = defaultTrack
        }
    }

    func cleanTrackInfo() {
        videoEnable = false
        videoTrack = nil
        videoTracks = []
        audioEnable = false
        audioTrack = nil
        audioTracks = []
    }

    func selectAudioTrack(index audioTrackIndex: Int) {
        guard audioTrack?.index != audioTrackIndex else { return }
        session.withResources(default: ()) { resources in
            guard let group = resources.asset.mediaSelectionGroup(
                forMediaCharacteristic: .audible
            ), let option = group.options.first(where: {
                Self.mediaSelectionTrackID(
                    from: $0.propertyList
                ) == audioTrackIndex
            }) else {
                return
            }
            resources.item.select(option, in: group)
            audioTrack = audioTracks.first {
                $0.index == audioTrackIndex
            }
        }
    }

    func playerTrack(from track: AVAssetTrack) -> IRPlayerTrack {
        let playerTrack = IRPlayerTrack()
        playerTrack.index = Int(track.trackID)
        playerTrack.name = Self.trackName(
            languageCode: track.languageCode,
            trackID: track.trackID
        )
        return playerTrack
    }

    static func trackName(
        languageCode: String?,
        trackID: CMPersistentTrackID
    ) -> String {
        IRAVPlayerTrackPolicy.trackName(
            languageCode: languageCode,
            trackID: trackID
        )
    }

    static func mediaSelectionTrackID(from propertyList: Any?) -> Int? {
        IRAVPlayerTrackPolicy.mediaSelectionTrackID(
            from: propertyList
        )
    }

    static func defaultTrack(
        from tracks: [IRPlayerTrack],
        propertyList: Any?
    ) -> IRPlayerTrack? {
        IRAVPlayerTrackPolicy.defaultTrack(
            from: tracks,
            propertyList: propertyList
        )
    }
}
