import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif

enum IRFFFormatContextBuilder {
    static let maximumSerializedHTTPHeaderByteCount =
        64 * 1024

    enum HTTPHeaderValidationFailure:
        Equatable
    {
        case invalidName
        case duplicateName
        case invalidValue
        case sizeLimitExceeded
    }

    enum HTTPHeaderSerializationResult:
        Equatable
    {
        case empty
        case serialized(String)
        case invalid(
            HTTPHeaderValidationFailure
        )
    }

    static func makeGeneration(
        contentURL: URL,
        videoFormat: IRVideoFormat,
        contentHeaders: [String: String],
        interruptState: IRFFFormatContextInterruptState
    ) -> Result<IRFFFormatContextGeneration, NSError> {
        let serializedHeaders: String?
        switch serializeHTTPHeaders(
            contentHeaders
        ) {
        case .empty:
            serializedHeaders = nil
        case let .serialized(value):
            serializedHeaders = value
        case .invalid:
            return .failure(
                makeError(
                    domain:
                        "Invalid HTTP header configuration",
                    code: .formatInvalidHeaders
                )
            )
        }

        guard let options = makeInputOptions(
            videoFormat: videoFormat,
            serializedHTTPHeaders:
                serializedHeaders
        ) else {
            return .failure(
                makeError(
                    domain:
                        "Could not create input options",
                    code: .formatOpenInput
                )
            )
        }

        var formatContext: UnsafeMutablePointer<AVFormatContext>? =
            avformat_alloc_context()
        guard let allocatedFormatContext = formatContext else {
            return .failure(
                makeError(
                    domain: "IRFFDecoderErrorCodeFormatCreate error",
                    code: .formatCreate
                )
            )
        }

        let callbackReference =
            interruptState.makeRetainedCallbackReference()
        allocatedFormatContext.pointee.interrupt_callback.callback =
            ffmpeg_interrupt_callback
        allocatedFormatContext.pointee.interrupt_callback.opaque =
            callbackReference

        let openResult = options.withMutableRawPointer {
            optionsPointer in
            avformat_open_input(
                &formatContext,
                contentURL.absoluteString,
                nil,
                &optionsPointer
            )
        }
        let openError = IRFFCheckErrorCode(
            openResult,
            errorCode: IRFFDecoderErrorCode.formatOpenInput.rawValue
        )
        guard openError == nil, let openedFormatContext = formatContext else {
            if let remainingFormatContext = formatContext {
                avformat_free_context(remainingFormatContext)
                formatContext = nil
            }
            IRFFFormatContextInterruptState
                .releaseRetainedCallbackReference(callbackReference)
            return .failure(
                openError ?? makeError(
                    domain: "IRFFDecoderErrorCodeFormatOpenInput error",
                    code: .formatOpenInput
                )
            )
        }

        let generation = IRFFFormatContextGeneration(
            formatContext: openedFormatContext,
            callbackReference: callbackReference
        )
        let streamInfoResult = avformat_find_stream_info(
            openedFormatContext,
            nil
        )
        if let streamInfoError = IRFFCheckErrorCode(
            streamInfoResult,
            errorCode:
                IRFFDecoderErrorCode.formatFindStreamInfo.rawValue
        ) {
            generation.close()
            return .failure(streamInfoError)
        }

        generation.metadata = IRFFDictionary.values(
            from: openedFormatContext.pointee.metadata
        ) ?? [:]
        let discoveredTracks = discoverTracks(
            in: openedFormatContext
        )
        generation.videoTracks = discoveredTracks.video
        generation.audioTracks = discoveredTracks.audio

        let videoError = openVideoTrack(in: generation)
        let audioError = openAudioTrack(in: generation)
        if let setupError = IRFFFormatContext.selectedSetupError(
            videoError: videoError,
            audioError: audioError
        ) {
            generation.close()
            return .failure(setupError)
        }
        return .success(generation)
    }

    static func serializeHTTPHeaders(
        _ headers: [String: String]
    ) -> HTTPHeaderSerializationResult {
        guard !headers.isEmpty else {
            return .empty
        }

        var normalized: [(
            canonicalName: String,
            name: String,
            value: String
        )] = []
        normalized.reserveCapacity(
            headers.count
        )
        var canonicalNames = Set<String>()
        canonicalNames.reserveCapacity(
            headers.count
        )

        for (name, rawValue) in headers {
            guard !name.isEmpty,
                  name.unicodeScalars.allSatisfy({
                      isHTTPTokenScalar($0.value)
                  }) else {
                return .invalid(.invalidName)
            }
            let canonicalName =
                name.lowercased()
            guard canonicalNames
                    .insert(canonicalName)
                    .inserted else {
                return .invalid(
                    .duplicateName
                )
            }
            guard rawValue.unicodeScalars
                    .allSatisfy({
                        isAllowedHTTPFieldValueScalar(
                            $0.value
                        )
                    }) else {
                return .invalid(
                    .invalidValue
                )
            }
            normalized.append(
                (
                    canonicalName,
                    name,
                    trimHTTPOptionalWhitespace(
                        rawValue
                    )
                )
            )
        }

        normalized.sort {
            if $0.canonicalName !=
                $1.canonicalName {
                return $0.canonicalName <
                    $1.canonicalName
            }
            return $0.name < $1.name
        }

        var totalByteCount = 0
        for header in normalized {
            let separatorByteCount =
                header.value.isEmpty ? 1 : 2
            let components = [
                header.name.utf8.count,
                separatorByteCount,
                header.value.utf8.count,
                2
            ]
            for component in components {
                let (nextTotal, overflow) =
                    totalByteCount
                        .addingReportingOverflow(
                            component
                        )
                guard !overflow,
                      nextTotal <=
                        maximumSerializedHTTPHeaderByteCount else {
                    return .invalid(
                        .sizeLimitExceeded
                    )
                }
                totalByteCount = nextTotal
            }
        }

        var serialized = ""
        serialized.reserveCapacity(
            totalByteCount
        )
        for header in normalized {
            serialized += header.name
            serialized += ":"
            if !header.value.isEmpty {
                serialized += " "
                serialized += header.value
            }
            serialized += "\r\n"
        }
        return .serialized(serialized)
    }

    static func makeInputOptions(
        videoFormat: IRVideoFormat,
        serializedHTTPHeaders: String?
    ) -> IRFFDictionary? {
        let options = IRFFDictionary()
        if videoFormat == .rtsp,
           !options.set(
               key: "rtsp_transport",
               value: "tcp"
           ) {
            return nil
        }
        if let serializedHTTPHeaders,
           !options.set(
               key: "headers",
               value:
                    serializedHTTPHeaders
           ) {
            return nil
        }
        return options
    }

    private static func isHTTPTokenScalar(
        _ scalar: UInt32
    ) -> Bool {
        switch scalar {
        case 48...57,
             65...90,
             97...122,
             33,
             35...39,
             42...43,
             45...46,
             94...96,
             124,
             126:
            return true
        default:
            return false
        }
    }

    private static func isAllowedHTTPFieldValueScalar(
        _ scalar: UInt32
    ) -> Bool {
        if scalar == 9 {
            return true
        }
        return scalar >= 32 &&
            scalar != 127
    }

    private static func trimHTTPOptionalWhitespace(
        _ value: String
    ) -> String {
        var lowerBound =
            value.startIndex
        var upperBound =
            value.endIndex
        while lowerBound < upperBound {
            let character =
                value[lowerBound]
            guard character == " " ||
                    character == "\t" else {
                break
            }
            lowerBound =
                value.index(
                    after: lowerBound
                )
        }
        while lowerBound < upperBound {
            let previous =
                value.index(
                    before: upperBound
                )
            let character = value[previous]
            guard character == " " ||
                    character == "\t" else {
                break
            }
            upperBound = previous
        }
        return String(
            value[lowerBound..<upperBound]
        )
    }

    static func makeCodecContext(
        trackIndex: Int,
        in formatContext: UnsafeMutablePointer<AVFormatContext>?,
        domain: String
    ) -> Result<UnsafeMutablePointer<AVCodecContext>, NSError> {
        guard let stream = IRFFFormatContext.stream(
            at: trackIndex,
            in: formatContext
        ),
              let codecParameters = stream.pointee.codecpar else {
            return .failure(
                makeError(
                    domain: "\(domain) stream not found",
                    code: .streamNotFound
                )
            )
        }

        var codecContext: UnsafeMutablePointer<AVCodecContext>? =
            avcodec_alloc_context3(nil)
        guard let allocatedCodecContext = codecContext else {
            return .failure(
                makeError(
                    domain: "\(domain) codec context create error",
                    code: .codecContextCreate
                )
            )
        }

        var result = avcodec_parameters_to_context(
            allocatedCodecContext,
            codecParameters
        )
        if let error = IRFFCheckErrorCode(
            result,
            errorCode:
                IRFFDecoderErrorCode.codecContextSetParam.rawValue
        ) {
            avcodec_free_context(&codecContext)
            return .failure(error)
        }
        allocatedCodecContext.pointee.pkt_timebase =
            stream.pointee.time_base

        guard let codec = IRFFFormatContext.decoder(
            for: allocatedCodecContext
        ) else {
            avcodec_free_context(&codecContext)
            return .failure(
                makeError(
                    domain: "\(domain) codec not found decoder",
                    code: .codecFindDecoder
                )
            )
        }
        allocatedCodecContext.pointee.codec_id = codec.pointee.id

        result = avcodec_open2(
            allocatedCodecContext,
            codec,
            nil
        )
        if let error = IRFFCheckErrorCode(
            result,
            errorCode: IRFFDecoderErrorCode.codecOpen2.rawValue
        ) {
            avcodec_free_context(&codecContext)
            return .failure(error)
        }
        return .success(allocatedCodecContext)
    }

    private static func discoverTracks(
        in formatContext: UnsafeMutablePointer<AVFormatContext>
    ) -> (video: [IRFFTrack], audio: [IRFFTrack]) {
        var videoTracks: [IRFFTrack] = []
        var audioTracks: [IRFFTrack] = []

        for index in 0..<Int(formatContext.pointee.nb_streams) {
            guard let stream = IRFFFormatContext.stream(
                at: index,
                in: formatContext
            ),
                  let codecParameters = stream.pointee.codecpar else {
                continue
            }
            let metadata = IRFFDictionary.values(
                from: stream.pointee.metadata
            ).map(IRFFMetadata.init(dictionary:))
            guard let track = IRFFFormatContext.track(
                index: index,
                codecType: codecParameters.pointee.codec_type,
                metadata: metadata
            ) else {
                continue
            }
            switch track.type {
            case .video:
                videoTracks.append(track)
            case .audio:
                audioTracks.append(track)
            case .subtitle:
                break
            }
        }
        return (videoTracks, audioTracks)
    }

    private static func openVideoTrack(
        in generation: IRFFFormatContextGeneration
    ) -> NSError? {
        var selectedError = makeError(
            domain: "video stream not found",
            code: .streamNotFound
        )

        for track in generation.videoTracks {
            guard let stream = IRFFFormatContext.stream(
                at: track.index,
                in: generation.formatContext
            ) else {
                continue
            }
            guard (
                stream.pointee.disposition
                    & AV_DISPOSITION_ATTACHED_PIC
            ) == 0 else {
                continue
            }

            switch makeCodecContext(
                trackIndex: track.index,
                in: generation.formatContext,
                domain: "video"
            ) {
            case let .success(codecContext):
                generation.installVideoCodecContext(codecContext)
                generation.videoTrack = track
                generation.videoTimebase = IRFFStreamGetTimebase(
                    stream,
                    defaultTimebase: 0.00004
                )
                generation.videoFPS = IRFFStreamGetFPS(
                    stream,
                    timebase: generation.videoTimebase
                )
                generation.videoPresentationSize =
                    IRFFFormatContext.presentationSize(
                        width: codecContext.pointee.width,
                        height: codecContext.pointee.height
                    )
                generation.videoAspect = IRFFFormatContext.videoAspect(
                    width: codecContext.pointee.width,
                    height: codecContext.pointee.height
                )
                return nil
            case let .failure(error):
                selectedError = error
            }
        }
        return selectedError
    }

    private static func openAudioTrack(
        in generation: IRFFFormatContextGeneration
    ) -> NSError? {
        var selectedError = makeError(
            domain: "audio stream not found",
            code: .streamNotFound
        )

        for track in generation.audioTracks {
            switch makeCodecContext(
                trackIndex: track.index,
                in: generation.formatContext,
                domain: "audio"
            ) {
            case let .success(codecContext):
                generation.installAudioCodecContext(codecContext)
                generation.audioTrack = track
                if let stream = IRFFFormatContext.stream(
                    at: track.index,
                    in: generation.formatContext
                ) {
                    generation.audioTimebase = IRFFStreamGetTimebase(
                        stream,
                        defaultTimebase: 0.000025
                    )
                }
                return nil
            case let .failure(error):
                selectedError = error
            }
        }
        return selectedError
    }

    private static func makeError(
        domain: String,
        code: IRFFDecoderErrorCode
    ) -> NSError {
        NSError(
            domain: domain,
            code: Int(code.rawValue),
            userInfo: nil
        )
    }
}
