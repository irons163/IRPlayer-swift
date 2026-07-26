//
//  IRFFAudioFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation

@objcMembers public class IRFFAudioFrame: IRFFFrame {
    var outputOffset: Int = 0
    private var sampleStorage: [Float] = []

    override var type: IRFFFrameType {
        return .audio
    }

    var sampleCapacity: Int {
        sampleStorage.count
    }

    var activeSampleCount: Int {
        guard let count = Self.sampleCapacity(
            forByteLength: size
        ),
        count <= sampleStorage.count else {
            return 0
        }
        return count
    }

    func setSamplesLength(_ samplesLength: Int) {
        guard let sampleCapacity = Self.sampleCapacity(forByteLength: samplesLength) else {
            sampleStorage = []
            size = 0
            outputOffset = 0
            return
        }

        if sampleStorage.count < sampleCapacity {
            sampleStorage = [Float](
                repeating: 0,
                count: sampleCapacity
            )
        }
        size = samplesLength
        outputOffset = 0
    }

    @discardableResult
    func withMutableSamples(
        _ body: (UnsafeMutableBufferPointer<Float>) -> Bool
    ) -> Bool {
        let count = activeSampleCount
        guard count > 0 else { return false }

        return sampleStorage.withUnsafeMutableBufferPointer {
            storage -> Bool in
            guard let baseAddress = storage.baseAddress,
                  count <= storage.count else {
                return false
            }
            return body(
                UnsafeMutableBufferPointer(
                    start: baseAddress,
                    count: count
                )
            )
        }
    }

    func sampleSnapshot() -> [Float]? {
        let count = activeSampleCount
        guard count > 0 else { return nil }
        return Array(sampleStorage.prefix(count))
    }

    func copySamples(
        to destination: UnsafeMutablePointer<Float>,
        byteOffset: Int,
        byteCount: Int
    ) -> Bool {
        copySamples(
            to: destination,
            byteOffset: byteOffset,
            byteCount: byteCount,
            availableByteCount: size
        )
    }

    /// Uses metadata captured before render ownership was transferred, so the
    /// real-time callback never has to acquire the frame transport lock.
    func copySamples(
        to destination: UnsafeMutablePointer<Float>,
        byteOffset: Int,
        byteCount: Int,
        availableByteCount: Int
    ) -> Bool {
        let stride = MemoryLayout<Float>.stride
        guard availableByteCount > 0,
              availableByteCount.isMultiple(of: stride),
              byteOffset >= 0,
              byteCount > 0,
              byteOffset.isMultiple(of: stride),
              byteCount.isMultiple(of: stride),
              let endOffset = Self.checkedSum(
                  byteOffset,
                  byteCount
              ),
              endOffset <= availableByteCount else {
            return false
        }

        return sampleStorage.withUnsafeBytes { storage in
            guard let baseAddress = storage.baseAddress,
                  availableByteCount <= storage.count,
                  endOffset <= storage.count else {
                return false
            }
            memcpy(
                UnsafeMutableRawPointer(destination),
                baseAddress.advanced(by: byteOffset),
                byteCount
            )
            return true
        }
    }

    static func sampleCapacity(forByteLength byteLength: Int) -> Int? {
        guard byteLength > 0 else { return nil }

        let stride = MemoryLayout<Float>.stride
        guard let adjustedByteLength = checkedSum(
            byteLength,
            stride - 1
        ) else {
            return nil
        }
        let capacity = adjustedByteLength / stride
        return capacity > 0 ? capacity : nil
    }

    private static func checkedSum(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int? {
        guard lhs >= 0, rhs >= 0 else { return nil }
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return !overflow && value >= 0 ? value : nil
    }
}
