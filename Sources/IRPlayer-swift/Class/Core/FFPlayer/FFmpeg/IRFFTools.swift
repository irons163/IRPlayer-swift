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
    return IRFFErrorPolicy.error(result: result, errorCode: errorCode)
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
    return IRFFDictionaryPolicy.foundationDictionary(from: avDictionary)
}
