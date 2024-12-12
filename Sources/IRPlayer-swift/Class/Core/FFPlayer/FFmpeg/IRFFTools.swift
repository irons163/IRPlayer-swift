//
//  IRFFTools.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/19.
//

import Foundation
import IRFFMpeg

enum IRFFDecoderErrorCode: Int {
    case formatCreate = 0
    case formatOpenInput
    case formatFindStreamInfo
    case streamNotFound
    case codecContextCreate
    case codecContextSetParam
    case codecFindDecoder
    case codecVideoSendPacket
    case codecAudioSendPacket
    case codecVideoReceiveFrame
    case codecAudioReceiveFrame
    case codecOpen2
    case audioSwrInit
}

func IRFFErrorLog(_ text: String) {
    print(text)
}

func IRPlayerLog(_ text: String) {
    print(text)
}

// MARK: - Utility Functions

func IRFFLog(context: UnsafeMutableRawPointer?, level: Int32, format: UnsafePointer<CChar>, args: CVaListPointer) {
#if IRFFFFmpegLogEnable
    let message = NSString(format: NSString(utf8String: format)! as String, arguments: args) as String
    print("IRFFLog: \(message)")
#endif
}

func IRFFCheckError(_ result: Int32) -> NSError? {
    return IRFFCheckErrorCode(result, errorCode: -1)
}

func IRFFCheckErrorCode(_ result: Int32, errorCode: Int) -> NSError? {
    guard result < 0 else { return nil }

    var errorBuffer = [CChar](repeating: 0, count: 256)
    av_strerror(result, &errorBuffer, errorBuffer.count)

    let errorString = String(cString: errorBuffer)
    let errorDescription = "ffmpeg code: \(result), ffmpeg msg: \(errorString)"
    return NSError(domain: errorDescription, code: errorCode, userInfo: nil)
}

func IRFFStreamGetTimebase(_ stream: UnsafePointer<AVStream>, defaultTimebase: Double) -> Double {
    let timebase: Double
    if stream.pointee.time_base.den > 0 && stream.pointee.time_base.num > 0 {
        timebase = av_q2d(stream.pointee.time_base)
    } else {
        timebase = defaultTimebase
    }
    return timebase
}

func IRFFStreamGetFPS(_ stream: UnsafePointer<AVStream>, timebase: Double) -> Double {
    let fps: Double
    if stream.pointee.avg_frame_rate.den > 0 && stream.pointee.avg_frame_rate.num > 0 {
        fps = av_q2d(stream.pointee.avg_frame_rate)
    } else if stream.pointee.r_frame_rate.den > 0 && stream.pointee.r_frame_rate.num > 0 {
        fps = av_q2d(stream.pointee.r_frame_rate)
    } else {
        fps = 1.0 / timebase
    }
    return fps
}

func IRFFFoundationBrigeOfAVDictionary(_ avDictionary: OpaquePointer?) -> [String: String]? {
    guard let avDictionary = avDictionary else { return nil }

    var dictionary: [String: String] = [:]
    var entry: UnsafeMutablePointer<AVDictionaryEntry>? = nil

    while let nextEntry = av_dict_get(avDictionary, "", entry, AV_DICT_IGNORE_SUFFIX) {
        if let key = nextEntry.pointee.key, let value = nextEntry.pointee.value {
            let keyString = String(cString: key)
            let valueString = String(cString: value)
            dictionary[keyString] = valueString
        }
        entry = nextEntry
    }

    return dictionary.isEmpty ? nil : dictionary
}
