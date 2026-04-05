// swift-tools-version:5.9
import PackageDescription

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
            exclude: ["IRPlayer-swift/ThirdParty", "IRPlayer-swift/Objc", "IRPlayer-swift/OpenGL"],
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
            path: "Tests"
        )
    ]
)

