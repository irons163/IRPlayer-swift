// swift-tools-version:5.9
import PackageDescription

let sourceAgentInstructionFiles = [
    "AGENTS.md",
    "IRPlayer-swift/Class/AGENTS.md",
    "IRPlayer-swift/Class/Core/AGENTS.md",
    "IRPlayer-swift/Class/Core/AVPlayer/AGENTS.md",
    "IRPlayer-swift/Class/Core/Audio/AGENTS.md",
    "IRPlayer-swift/Class/Core/Config/AGENTS.md",
    "IRPlayer-swift/Class/Core/Controller/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/Metal/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/RenderKit/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/RenderKit/Mode/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/RenderKit/Params/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/RenderKit/Program/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/RenderKit/Projection/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/RenderKit/Scope/AGENTS.md",
    "IRPlayer-swift/Class/Core/Display/RenderKit/Transform/AGENTS.md",
    "IRPlayer-swift/Class/Core/FFPlayer/AGENTS.md",
    "IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/AGENTS.md",
    "IRPlayer-swift/Class/Core/FFPlayer/FFmpeg/Frame/AGENTS.md",
    "IRPlayer-swift/Class/Core/Matrix/AGENTS.md",
    "IRPlayer-swift/Class/Core/Tools/AGENTS.md",
    "IRPlayer-swift/Class/Platform/AGENTS.md"
]

let package = Package(
    name: "IRPlayer",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "IRPlayer",
            targets: ["IRPlayerSwift"]
        )
    ],
    targets: [
        // Configure targets to use Metal instead of OpenGL
        .target(
            name: "IRPlayerSwift",
            dependencies: ["IRPlayerObjc", "IRFFMpeg"],
            path: "Sources",
            exclude: ["IRPlayer-swift/ThirdParty", "IRPlayer-swift/Objc"] + sourceAgentInstructionFiles,
            resources: [
                .process("IRPlayer-swift/Class/Core/Display/Metal/IRMetalShaders.metal")
            ],
            swiftSettings: [
                .define("IRPLATFORM_TARGET_OS_IPHONE_OR_TV"),
                .define("IRPLATFORM_TARGET_OS_MAC_OR_IPHONE"),
                .define("IR_USE_METAL")
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .target(
            name: "IRPlayerObjc",
            dependencies: ["libavutil"],
            path: "Sources/IRPlayer-swift/Objc",
            cSettings: [
                .define("IR_USE_METAL")
            ]
        ),
        .target(
            name: "IRFFMpeg",
            dependencies: [
                "libavcodec",
                "libavformat",
                "libavutil",
                "libswresample",
                "libswscale"
            ],
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg",
            publicHeadersPath: "include",
            cSettings: [
                .define("IR_USE_METAL")
            ]
        ),
        .binaryTarget(
            name: "libavcodec",
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs/libavcodec.xcframework"
        ),
        .binaryTarget(
            name: "libavformat",
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs/libavformat.xcframework"
        ),
        .binaryTarget(
            name: "libavutil",
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs/libavutil.xcframework"
        ),
        .binaryTarget(
            name: "libavdevice",
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs/libavdevice.xcframework"
        ),
        .binaryTarget(
            name: "libavfilter",
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs/libavfilter.xcframework"
        ),
        .binaryTarget(
            name: "libswresample",
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs/libswresample.xcframework"
        ),
        .binaryTarget(
            name: "libswscale",
            path: "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs/libswscale.xcframework"
        ),
        .testTarget(
            name: "IRPlayer-swiftTests",
            dependencies: ["IRPlayerSwift"],
            path: "Tests",
            exclude: ["AGENTS.md"]
        )
    ]
)
