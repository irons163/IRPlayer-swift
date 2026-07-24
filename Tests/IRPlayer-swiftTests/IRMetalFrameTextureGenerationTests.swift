import CoreVideo
import IRFFMpeg
import Metal
import XCTest
@testable import IRPlayer_swift

final class IRMetalFrameTextureGenerationTests:
    XCTestCase
{
    func testNV12GenerationOwnsBothCoreVideoPlanes() throws {
        let renderer = try makeRenderer()
        let frame = IRFFCVYUVVideoFrame(
            pixelBuffer: try makePixelBuffer(
                format:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            )
        )
        let generation = try XCTUnwrap(
            renderer.makeFrameTextureGeneration(from: frame)
        )

        XCTAssertEqual(
            generation.diagnostics,
            IRMetalFrameTextureDiagnostics(
                format: .nv12,
                textureCount: 2,
                coreVideoTextureCount: 2,
                retainsSourcePixelBuffer: true
            )
        )
        guard case let .nv12(y, uv) = generation.textures else {
            return XCTFail("expected NV12 textures")
        }
        XCTAssertEqual(y.width, 2)
        XCTAssertEqual(y.height, 2)
        XCTAssertEqual(y.pixelFormat, .r8Unorm)
        XCTAssertEqual(uv.width, 1)
        XCTAssertEqual(uv.height, 1)
        XCTAssertEqual(uv.pixelFormat, .rg8Unorm)
    }

    func testBGRAGenerationOwnsCoreVideoTexture() throws {
        let renderer = try makeRenderer()
        let frame = IRFFCVYUVVideoFrame(
            pixelBuffer: try makePixelBuffer(
                format: kCVPixelFormatType_32BGRA
            )
        )
        let generation = try XCTUnwrap(
            renderer.makeFrameTextureGeneration(from: frame)
        )

        XCTAssertEqual(
            generation.diagnostics,
            IRMetalFrameTextureDiagnostics(
                format: .bgra,
                textureCount: 1,
                coreVideoTextureCount: 1,
                retainsSourcePixelBuffer: true
            )
        )
        guard case let .bgra(texture) =
                generation.textures else {
            return XCTFail("expected BGRA texture")
        }
        XCTAssertEqual(texture.width, 2)
        XCTAssertEqual(texture.height, 2)
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
    }

    func testI420GenerationPublishesThreeManagedTextures() throws {
        let renderer = try makeRenderer()

        try withI420Frame { frame in
            let generation = try XCTUnwrap(
                renderer.makeFrameTextureGeneration(from: frame)
            )
            XCTAssertEqual(
                generation.diagnostics,
                IRMetalFrameTextureDiagnostics(
                    format: .i420,
                    textureCount: 3,
                    coreVideoTextureCount: 0,
                    retainsSourcePixelBuffer: false
                )
            )
            guard case let .i420(y, u, v) =
                    generation.textures else {
                return XCTFail("expected I420 textures")
            }
            XCTAssertEqual(y.pixelFormat, .r8Unorm)
            XCTAssertEqual(u.pixelFormat, .r8Unorm)
            XCTAssertEqual(v.pixelFormat, .r8Unorm)
        }
    }

    func testRGBGenerationPublishesManagedTexture() throws {
        let renderer = try makeRenderer()
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 2,
                height: 2,
                pixelFormat: .bgra32,
                bytesPerRow: 8,
                data: Data(repeating: 0xff, count: 16)
            )
        )
        let generation = try XCTUnwrap(
            renderer.makeFrameTextureGeneration(from: frame)
        )

        XCTAssertEqual(
            generation.diagnostics,
            IRMetalFrameTextureDiagnostics(
                format: .rgb,
                textureCount: 1,
                coreVideoTextureCount: 0,
                retainsSourcePixelBuffer: false
            )
        )
        guard case let .rgb(texture) =
                generation.textures else {
            return XCTFail("expected RGB texture")
        }
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
    }

    func testUnsupportedAndIncompleteFramesPublishNothing()
        throws
    {
        let renderer = try makeRenderer()
        let unsupported = IRFFVideoFrame()
        let emptyI420 = IRFFAVYUVVideoFrame()

        XCTAssertNil(
            renderer.makeFrameTextureGeneration(
                from: unsupported
            )
        )
        XCTAssertNil(
            renderer.makeFrameTextureGeneration(
                from: emptyI420
            )
        )
    }

    private func makeRenderer() throws -> IRMetalRenderer {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = IRMetalRenderer(device: device) else {
            throw XCTSkip("Metal renderer unavailable")
        }
        return renderer
    }

    private func makePixelBuffer(
        width: Int = 2,
        height: Int = 2,
        format: OSType
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String:
                true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess,
              let pixelBuffer else {
            throw XCTSkip("CVPixelBuffer unavailable")
        }
        return pixelBuffer
    }

    private func withI420Frame(
        _ body: (IRFFAVYUVVideoFrame) throws -> Void
    ) throws {
        var y = [UInt8](repeating: 0x10, count: 4)
        var u = [UInt8](repeating: 0x80, count: 1)
        var v = [UInt8](repeating: 0x80, count: 1)
        var avFrame = AVFrame()
        avFrame.format = AV_PIX_FMT_YUV420P.rawValue
        avFrame.linesize.0 = 2
        avFrame.linesize.1 = 1
        avFrame.linesize.2 = 1
        let frame = IRFFAVYUVVideoFrame()

        try y.withUnsafeMutableBufferPointer { yBuffer in
            try u.withUnsafeMutableBufferPointer { uBuffer in
                try v.withUnsafeMutableBufferPointer { vBuffer in
                    avFrame.data.0 = yBuffer.baseAddress
                    avFrame.data.1 = uBuffer.baseAddress
                    avFrame.data.2 = vBuffer.baseAddress
                    withUnsafePointer(to: &avFrame) { pointer in
                        frame.setFrameData(
                            pointer,
                            width: 2,
                            height: 2
                        )
                    }
                    try body(frame)
                }
            }
        }
    }
}
