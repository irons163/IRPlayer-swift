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
    IRFFRuntimeDebugOutput.write(text)
}

func IRPlayerLog(_ text: String) {
    IRFFRuntimeDebugOutput.write(text)
}

enum IRFFRuntimeDebugOutput {
    static var isEnabled: Bool {
        IRFFRuntimeDebugOutputPolicy.isEnabled
    }

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        IRFFRuntimeDebugOutputPolicy.write(message())
    }
}

// MARK: - Utility Functions

func IRFFLog(context: UnsafeMutableRawPointer?, level: Int32, format: UnsafePointer<CChar>, args: CVaListPointer) {
    IRFFLogPolicy.write(context: context, level: level, format: format, args: args)
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

func IRFFFinitePositiveValueOrDefault(_ value: Double, defaultValue: Double) -> Double {
    return IRFFStreamTimingPolicy.finitePositiveValueOrDefault(value, defaultValue: defaultValue)
}

func IRFFStreamGetTimebase(_ stream: UnsafePointer<AVStream>, defaultTimebase: Double) -> Double {
    return IRFFStreamTimingPolicy.timebase(stream, defaultTimebase: defaultTimebase)
}

func IRFFStreamGetFPS(_ stream: UnsafePointer<AVStream>, timebase: Double) -> Double {
    return IRFFStreamTimingPolicy.fps(stream, timebase: timebase)
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
