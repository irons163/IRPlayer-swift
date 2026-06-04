import Foundation

enum IRFFDecoderAudioPolicy {

    static func audioPacketError(fromPacketResult packetResult: Int) -> NSError? {
        return IRFFCheckErrorCode(Int32(packetResult), errorCode: IRFFDecoderErrorCode.codecAudioSendPacket.rawValue)
    }

    static func bufferedDurationTransition(bufferedDuration: TimeInterval, endOfFile: Bool) -> IRFFDecoder.BufferedDurationTransition {
        let normalizedDuration = bufferedDuration.isFinite && bufferedDuration > 0.000001 ? bufferedDuration : 0
        return IRFFDecoder.BufferedDurationTransition(
            bufferedDuration: normalizedDuration,
            shouldFinishPlayback: normalizedDuration <= 0 && endOfFile
        )
    }

    static func shouldFetchAudioFrame(closed: Bool,
                                      seeking: Bool,
                                      buffering: Bool,
                                      paused: Bool,
                                      playbackFinished: Bool,
                                      audioEnabled: Bool) -> Bool {
        return !closed && !seeking && !buffering && !paused && !playbackFinished && audioEnabled
    }
}
