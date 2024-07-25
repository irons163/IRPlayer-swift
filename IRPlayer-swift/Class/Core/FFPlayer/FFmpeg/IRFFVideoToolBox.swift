//
//  IRFFVideoToolBox.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/25.
//

import Foundation
import VideoToolbox

enum IRFFVideoToolBoxErrorCode: Error {
    case extradataSize
    case extradataData
    case createFormatDescription
    case createSession
    case notH264
}

class IRFFVideoToolBox {
    private var codecContext: UnsafeMutablePointer<AVCodecContext>
    private var vtSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    var decodeStatus: OSStatus = noErr
    var decodeOutput: CVImageBuffer?

    var vtSessionToken: Bool = false
    var needConvertNALSize3To4: Bool = false

    init(codecContext: UnsafeMutablePointer<AVCodecContext>) {
        self.codecContext = codecContext
    }

    static func videoToolBox(with codecContext: UnsafeMutablePointer<AVCodecContext>) -> IRFFVideoToolBox {
        return IRFFVideoToolBox(codecContext: codecContext)
    }

    func trySetupVTSession() -> Bool {
        if !self.vtSessionToken {
            do {
                try self.setupVTSession()
                self.vtSessionToken = true
            } catch {
                return false
            }
        }
        return self.vtSessionToken
    }

    func setupVTSession() throws {
        let codecID = codecContext.pointee.codec_id
        guard let extradata = codecContext.pointee.extradata else {
            throw IRFFVideoToolBoxErrorCode.extradataSize
        }
        let extradataSize = codecContext.pointee.extradata_size

        if codecID == AV_CODEC_ID_H264 {
            if extradataSize < 7 {
                throw IRFFVideoToolBoxErrorCode.extradataSize
            }

            if extradata[0] == 1 {
                if extradata[4] == 0xFE {
                    extradata[4] = 0xFF
                    self.needConvertNALSize3To4 = true
                }
                self.formatDescription = createFormatDescription(codecType: kCMVideoCodecType_H264, width: codecContext.pointee.width, height: codecContext.pointee.height, extradata: extradata, extradataSize: extradataSize)
                if self.formatDescription == nil {
                    throw IRFFVideoToolBoxErrorCode.createFormatDescription
                }

                let destinationPixelBufferAttributes: [CFString: Any] = [
                    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferWidthKey: codecContext.pointee.width,
                    kCVPixelBufferHeightKey: codecContext.pointee.height
                ]

                var outputCallbackRecord = VTDecompressionOutputCallbackRecord()
                outputCallbackRecord.decompressionOutputCallback = IRFFVideoToolBox.outputCallback
                outputCallbackRecord.decompressionOutputRefCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

                let status = VTDecompressionSessionCreate(
                    allocator: kCFAllocatorDefault,
                    formatDescription: self.formatDescription!,
                    decoderSpecification: nil,
                    imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
                    outputCallback: &outputCallbackRecord,
                    decompressionSessionOut: &self.vtSession
                )

                if status != noErr {
                    throw IRFFVideoToolBoxErrorCode.createSession
                }
            } else {
                throw IRFFVideoToolBoxErrorCode.extradataData
            }
        } else {
            throw IRFFVideoToolBoxErrorCode.notH264
        }
    }

    func cleanVTSession() {
        self.formatDescription = nil
        if let vtSession = self.vtSession {
            VTDecompressionSessionWaitForAsynchronousFrames(vtSession)
            VTDecompressionSessionInvalidate(vtSession)
            self.vtSession = nil
        }
        self.needConvertNALSize3To4 = false
        self.vtSessionToken = false
    }

    func cleanDecodeInfo() {
        self.decodeStatus = noErr
        self.decodeOutput = nil
    }

    func sendPacket(_ packet: AVPacket) -> Bool {
        guard self.trySetupVTSession() else { return false }
        self.cleanDecodeInfo()

        var result = false
        var blockBuffer: CMBlockBuffer?
        var status: OSStatus = noErr

        if self.needConvertNALSize3To4 {
            var ioContext: UnsafeMutablePointer<AVIOContext>?
            if avio_open_dyn_buf(&ioContext) < 0 {
                status = -1900
            } else {
                var nalSize: UInt32 = 0
                let end = packet.data?.advanced(by: Int(packet.size))
                var nalStart = packet.data!
                while nalStart < end! {
                    nalSize = (UInt32(nalStart[0]) << 16) | (UInt32(nalStart[1]) << 8) | UInt32(nalStart[2])
                    avio_wb32(ioContext, nalSize)
                    nalStart += 3
                    avio_write(ioContext, nalStart, Int32(nalSize))
                    nalStart += UnsafeMutablePointer<UInt8>.Stride(nalSize)
                }
                var demuxBuffer: UnsafeMutablePointer<UInt8>?
                let demuxSize = avio_close_dyn_buf(ioContext, &demuxBuffer)
                status = CMBlockBufferCreateWithMemoryBlock(
                    allocator: nil,
                    memoryBlock: demuxBuffer!,
                    blockLength: Int(demuxSize),
                    blockAllocator: kCFAllocatorNull,
                    customBlockSource: nil,
                    offsetToData: 0,
                    dataLength: Int(packet.size),
                    flags: 0,
                    blockBufferOut: &blockBuffer
                )
            }
        } else {
            status = CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: packet.data!,
                blockLength: Int(packet.size),
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: Int(packet.size),
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        if status == noErr {
            var sampleBuffer: CMSampleBuffer?
            status = CMSampleBufferCreate(
                allocator: nil,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: self.formatDescription!,
                sampleCount: 1,
                sampleTimingEntryCount: 0,
                sampleTimingArray: nil,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )

            if status == noErr {
                status = VTDecompressionSessionDecodeFrame(
                    self.vtSession!,
                    sampleBuffer: sampleBuffer!,
                    flags: [],
                    frameRefcon: nil,
                    infoFlagsOut: nil
                )

                if status == noErr, self.decodeStatus == noErr, self.decodeOutput != nil {
                    result = true
                }
            }
        }
        return result
    }

    func imageBuffer() -> CVImageBuffer? {
        if self.decodeStatus == noErr, let decodeOutput = self.decodeOutput {
            return decodeOutput
        }
        return nil
    }

    func flush() {
        self.cleanVTSession()
        self.cleanDecodeInfo()
    }

    deinit {
        self.flush()
        print("IRFFVideoToolBox release")
    }

    private static let outputCallback: VTDecompressionOutputCallback = { (
        decompressionOutputRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTDecodeInfoFlags,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp: CMTime,
        presentationDuration: CMTime
    ) in
            let videoToolBox = Unmanaged<IRFFVideoToolBox>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
            videoToolBox.decodeStatus = status
            videoToolBox.decodeOutput = imageBuffer
    }

    private func createFormatDescription(codecType: CMVideoCodecType, width: Int32, height: Int32, extradata: UnsafePointer<UInt8>, extradataSize: Int32) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?
        var status: OSStatus

        let par: CFMutableDictionary = [
            "HorizontalSpacing": 0,
            "VerticalSpacing": 0
        ] as! CFMutableDictionary as CFMutableDictionary

        let atoms: CFMutableDictionary = [
            "avcC": CFDataCreate(nil, extradata, CFIndex(extradataSize))
        ] as! CFMutableDictionary as CFMutableDictionary

        let extensions: CFMutableDictionary = [
            "CVImageBufferChromaLocationBottomField": "left" as CFString,
            "CVImageBufferChromaLocationTopField": "left" as CFString,
            "FullRangeVideo": false,
            "CVPixelAspectRatio": par,
            "SampleDescriptionExtensionAtoms": atoms
        ] as! CFMutableDictionary

        status = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: codecType,
            width: width,
            height: height,
            extensions: extensions,
            formatDescriptionOut: &formatDescription
        )

        return status == noErr ? formatDescription : nil
    }
}
