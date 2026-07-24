//
//  IRFFAVYUVVideoFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation
import CoreVideo
import IRFFMpeg

@objcMembers public class IRFFAVYUVVideoFrame: IRFFVideoFrame {
    private let planeLock = NSLock()
    private var planeStorage = IRFFYUVPlaneStorage()
    private var planeGeneration: UInt64 = 0
    private var activePixelFormat: AVPixelFormat?
    private var activeWidth = 0
    private var activeHeight = 0
    private var activeChromaWidth = 0
    private var activeChromaHeight = 0
    private var cachedImage: (
        generation: UInt64,
        image: IRPLFImage
    )?

    override var type: IRFFFrameType {
        return .avyuvVideo
    }

    var planeCapacities: [Int] {
        planeLock.lock()
        defer { planeLock.unlock() }
        return planeStorage.capacities
    }

    static func shouldAcceptFrameData(
        width: Int,
        height: Int,
        hasLuma: Bool,
        hasChromaB: Bool,
        hasChromaR: Bool,
        linesizeY: Int32,
        linesizeU: Int32,
        linesizeV: Int32
    ) -> Bool {
        guard hasLuma,
              hasChromaB,
              hasChromaR else {
            return false
        }
        return IRYUVPlaneLayout.i420(
            width: width,
            height: height,
            linesizeY: linesizeY,
            linesizeU: linesizeU,
            linesizeV: linesizeV
        ) != nil
    }

    func setFrameData(
        _ frame: UnsafePointer<AVFrame>,
        width: Int,
        height: Int
    ) {
        let linesizeY = frame.pointee.linesize.0
        let linesizeU = frame.pointee.linesize.1
        let linesizeV = frame.pointee.linesize.2
        guard let luma = frame.pointee.data.0,
              let chromaB = frame.pointee.data.1,
              let chromaR = frame.pointee.data.2,
              let layouts = IRYUVPlaneLayout.i420(
                  width: width,
                  height: height,
                  linesizeY: linesizeY,
                  linesizeU: linesizeU,
                  linesizeV: linesizeV
              ) else {
            flush()
            return
        }

        planeLock.lock()
        defer { planeLock.unlock() }
        guard planeStorage.update(
            lumaSource: luma,
            chromaBSource: chromaB,
            chromaRSource: chromaR,
            layouts: layouts
        ) else {
            deactivateLocked()
            return
        }

        planeGeneration &+= 1
        activePixelFormat = AVPixelFormat(
            rawValue: frame.pointee.format
        )
        activeWidth = width
        activeHeight = height
        activeChromaWidth = layouts.chromaB.width
        activeChromaHeight = layouts.chromaB.height
        size = planeStorage.totalByteCount
        cachedImage = nil
    }

    func planeSnapshot() -> IRFFYUVPlaneSnapshot? {
        planeLock.lock()
        defer { planeLock.unlock() }
        return snapshotLocked()
    }

    func flush() {
        planeLock.lock()
        deactivateLocked()
        planeLock.unlock()
    }

    @nonobjc
    override func dimensionSnapshot() -> IRFFVideoDimensions {
        planeLock.lock()
        defer { planeLock.unlock() }
        return IRFFVideoDimensions.make(
            width: activeWidth,
            height: activeHeight
        ) ?? .zero
    }

    @discardableResult
    public override func setDimensions(
        width: Int,
        height: Int
    ) -> Bool {
        guard let dimensions = IRFFVideoDimensions.make(
            width: width,
            height: height
        ) else {
            return false
        }
        return dimensions == dimensionSnapshot()
    }

    override func prepareForReuse() {
        flush()
        super.prepareForReuse()
    }

    func image() -> IRPLFImage? {
        planeLock.lock()
        if let cachedImage,
           cachedImage.generation == planeGeneration {
            planeLock.unlock()
            return cachedImage.image
        }
        guard let snapshot = snapshotLocked() else {
            planeLock.unlock()
            return nil
        }
        planeLock.unlock()

        guard let image = snapshot.image() else {
            return nil
        }

        planeLock.lock()
        defer { planeLock.unlock() }
        guard planeGeneration == snapshot.generation,
              snapshotLocked() != nil else {
            return nil
        }
        cachedImage = (
            generation: snapshot.generation,
            image: image
        )
        return image
    }

    private func snapshotLocked() -> IRFFYUVPlaneSnapshot? {
        guard let activePixelFormat,
              activeWidth > 0,
              activeHeight > 0,
              activeChromaWidth > 0,
              activeChromaHeight > 0,
              planeStorage.totalByteCount > 0 else {
            return nil
        }
        return planeStorage.snapshot(
            generation: planeGeneration,
            width: activeWidth,
            height: activeHeight,
            chromaWidth: activeChromaWidth,
            chromaHeight: activeChromaHeight,
            pixelFormat: activePixelFormat
        )
    }

    private func deactivateLocked() {
        planeStorage.deactivate()
        planeGeneration &+= 1
        activePixelFormat = nil
        activeWidth = 0
        activeHeight = 0
        activeChromaWidth = 0
        activeChromaHeight = 0
        size = 0
        cachedImage = nil
    }
}
