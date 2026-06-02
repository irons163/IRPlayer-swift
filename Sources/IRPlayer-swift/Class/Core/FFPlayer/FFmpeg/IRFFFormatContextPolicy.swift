import CoreGraphics
import Foundation
import IRFFMpeg
import IRPlayerObjc

enum IRFFFormatContextPolicy {

    static func dictionaryOptionWasApplied(_ result: Int32) -> Bool {
        return result >= 0
    }

    static func durationSeconds(from duration: Int64) -> TimeInterval {
        guard duration != IR_AV_NOPTS_VALUE else {
            return TimeInterval(MAXFLOAT)
        }
        guard duration >= 0 else { return 0 }
        let seconds = TimeInterval(duration) / TimeInterval(AV_TIME_BASE)
        return seconds.isFinite ? seconds : 0
    }

    static func bitrateKbps(from bitRate: Int64) -> TimeInterval {
        guard bitRate >= 0 else { return 0 }
        let bitrate = TimeInterval(bitRate) / 1000.0
        return bitrate.isFinite ? bitrate : 0
    }

    static func presentationSize(width: Int32, height: Int32) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    static func selectedSetupError(videoError: NSError?, audioError: NSError?) -> NSError? {
        guard let videoError, let audioError else {
            return nil
        }

        if videoError.code == IRFFDecoderErrorCode.streamNotFound.rawValue && audioError.code != IRFFDecoderErrorCode.streamNotFound.rawValue {
            return audioError
        }
        return videoError
    }

    static func seekTimestamp(for time: TimeInterval) -> Int64? {
        guard time.isFinite, time >= 0 else { return nil }
        let timestamp = time * Double(AV_TIME_BASE)
        guard timestamp.isFinite,
              timestamp >= 0,
              timestamp <= Double(Int64.max) else {
            return nil
        }
        return Int64(timestamp)
    }

    static func track(index: Int, codecType: AVMediaType, metadata: IRFFMetadata?) -> IRFFTrack? {
        guard index >= 0 else { return nil }

        switch codecType {
        case AVMEDIA_TYPE_VIDEO:
            return IRFFTrack(index: index, type: .video, metadata: metadata)
        case AVMEDIA_TYPE_AUDIO:
            return IRFFTrack(index: index, type: .audio, metadata: metadata)
        default:
            return nil
        }
    }

    static func videoAspect(width: Int32, height: Int32) -> CGFloat {
        guard width > 0, height > 0 else { return 0 }
        let aspect = CGFloat(width) / CGFloat(height)
        return aspect.isFinite ? aspect : 0
    }

    static func audioTrackSelectionAction(requestedIndex: Int,
                                          currentIndex: Int?,
                                          containsRequestedTrack: Bool) -> IRFFFormatContext.AudioTrackSelectionAction {
        guard requestedIndex >= 0,
              requestedIndex != (currentIndex ?? -1),
              containsRequestedTrack else {
            return .noChange
        }
        return .select
    }
}
