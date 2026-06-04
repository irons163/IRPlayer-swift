import IRFFMpeg

enum IRFFDecoderCodecContextPolicy {

    static func videoCodecContext(from formatContext: IRFFFormatContext?) -> UnsafeMutablePointer<AVCodecContext>? {
        guard formatContext?.videoEnable == true else { return nil }
        return formatContext?.videoCodecContext
    }

    static func audioCodecContext(from formatContext: IRFFFormatContext?) -> UnsafeMutablePointer<AVCodecContext>? {
        guard formatContext?.audioEnable == true else { return nil }
        return formatContext?.audioCodecContext
    }
}
