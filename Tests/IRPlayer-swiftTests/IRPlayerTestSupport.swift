//
//  IRPlayerTestSupport.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import Darwin
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class FormatContextInterruptDelegate: IRFFFormatContextDelegate {
    var shouldInterrupt: Bool

    init(shouldInterrupt: Bool) {
        self.shouldInterrupt = shouldInterrupt
    }

    func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool {
        shouldInterrupt
    }
}

final class ShaderParamsDelegateSpy: IRGLShaderParamsDelegate {
    private(set) var outputSizes: [(width: Int, height: Int)] = []

    func didUpdateOutputWH(_ w: Int, _ h: Int) {
        outputSizes.append((w, h))
    }
}

func loadedFFPlayer(from player: IRPlayerImp) -> IRFFPlayer? {
    player.existingPlaybackBackend(for: .ffmpeg) as? IRFFPlayer
}

func loadedAVPlayer(from player: IRPlayerImp) -> IRAVPlayer? {
    player.existingPlaybackBackend(for: .avFoundation) as? IRAVPlayer
}

func captureStandardOutput(_ body: () -> Void) -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    fflush(stdout)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    body()

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func makeTinyPCM16WAVFile() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irff-audio-decoder-\(UUID().uuidString).wav")
    try? FileManager.default.removeItem(at: url)

    let channelCount: UInt16 = 2
    let sampleRate: UInt32 = 48_000
    let bitsPerSample: UInt16 = 16
    let frameCount = 2_048
    let blockAlign = channelCount * bitsPerSample / 8
    let byteRate = sampleRate * UInt32(blockAlign)
    var samples = Data()
    samples.reserveCapacity(frameCount * Int(blockAlign))
    for frame in 0..<frameCount {
        let left = Int16((frame % 128) * 128)
        let right = Int16(-left)
        samples.appendLittleEndian(left)
        samples.appendLittleEndian(right)
    }

    var data = Data()
    data.appendASCII("RIFF")
    data.appendLittleEndian(UInt32(36 + samples.count))
    data.appendASCII("WAVE")
    data.appendASCII("fmt ")
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(channelCount)
    data.appendLittleEndian(sampleRate)
    data.appendLittleEndian(byteRate)
    data.appendLittleEndian(blockAlign)
    data.appendLittleEndian(bitsPerSample)
    data.appendASCII("data")
    data.appendLittleEndian(UInt32(samples.count))
    data.append(samples)

    try data.write(to: url, options: .atomic)
    return url
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
