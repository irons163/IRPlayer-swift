import Foundation

enum IRFFDecoderPacketPolicy {

    static func packetBufferBackpressureSleepInterval(audioSize: Int,
                                                      videoPacketSize: Int,
                                                      maxBufferSize: Int = 20 * 1024 * 1024,
                                                      paused: Bool) -> TimeInterval? {
        guard audioSize >= 0,
              videoPacketSize >= 0,
              maxBufferSize > 0 else {
            return nil
        }
        if audioSize >= maxBufferSize || videoPacketSize >= maxBufferSize {
            return paused ? 0.5 : 0.1
        }
        guard videoPacketSize >= maxBufferSize - audioSize else {
            return nil
        }
        return paused ? 0.5 : 0.1
    }

    static func readPacketEOFTransition(readFrameResult: Int32?) -> IRFFDecoder.ReadPacketEOFTransition? {
        guard (readFrameResult ?? -1) < 0 else {
            return nil
        }
        return IRFFDecoder.ReadPacketEOFTransition(
            endOfFile: true,
            videoEndOfFile: true,
            shouldFinishReadLoop: true,
            shouldNotifyDelegate: true
        )
    }

    static func packetRoute(streamIndex: Int32, videoTrackIndex: Int?, audioTrackIndex: Int?) -> IRFFDecoder.PacketRoute {
        if let videoTrackIndex, streamIndex == Int32(videoTrackIndex) {
            return .video
        }
        if let audioTrackIndex, streamIndex == Int32(audioTrackIndex) {
            return .audio
        }
        return .ignored
    }
}
