// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_litert",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-litert", type: .dynamic, targets: ["flutter_litert"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        // These xcframeworks must be produced with `xcodebuild -create-xcframework`,
        // which writes an Info.plist whose slice identifiers match the on-disk
        // directories. A hand-assembled build previously shipped a mismatch: the
        // Info.plist declared `ios-arm64_x86_64-simulator` while the actual dir and
        // (arm64-only) binary were `ios-arm64-simulator`, so SPM looked for a slice
        // that didn't exist ("There is no XCFramework found at ..."). Each per-slice
        // `.framework` bundle must also contain its own `Info.plist`, or SPM's embed
        // step fails ("framework did not contain an Info.plist"). Both were the
        // root cause of iOS SPM builds breaking; CocoaPods was unaffected because its
        // podspec rewrites the Info.plist at install time.
        //
        // The TensorFlowLite* simulator slices are arm64-only (Bazel
        // `--cpu=ios_sim_arm64`), so iOS-simulator SPM builds work on Apple
        // Silicon only. For x86_64 (Intel) simulator support, also build
        // `--cpu=ios_sim_x86_64`, lipo into a universal simulator slice, and
        // recreate the xcframework. (The LiteRt* targets below already ship
        // universal simulator slices: arm64 plus an empty x86_64 stub, see
        // scripts/wrap_litert_ios_frameworks.sh.)
        .binaryTarget(
            name: "TensorFlowLiteC",
            url: "https://github.com/hugocornellier/flutter_litert/releases/download/flex-v1.1.1/TensorFlowLiteC-spm.xcframework.zip",
            checksum: "18701b6fdf438394dcacf0ed2d0412eefcd59f70db7a10ead5b8b68dbbc0b382"
        ),
        .binaryTarget(
            name: "TensorFlowLiteCMetal",
            url: "https://github.com/hugocornellier/flutter_litert/releases/download/flex-v1.1.1/TensorFlowLiteCMetal-spm.xcframework.zip",
            checksum: "0a87767a22aee42309432c3d8f82f87a92712af37968432460193a027aedb481"
        ),
        .binaryTarget(
            name: "TensorFlowLiteCCoreML",
            url: "https://github.com/hugocornellier/flutter_litert/releases/download/coreml-ios-v1.1.0/TensorFlowLiteCCoreML-spm.xcframework.zip",
            checksum: "4d6932bbdf5791cd9d53b689dd796b47d7bd4595204aa04f88d29921701192eb"
        ),
        .target(
            name: "flutter_litert",
            dependencies: [
                .target(name: "TensorFlowLiteC"),
                .target(name: "TensorFlowLiteCMetal"),
                .target(name: "TensorFlowLiteCCoreML"),
                .target(name: "flutter_litert_delegate_symbols"),
                .target(name: "flutter_litert_custom_ops"),
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/flutter_litert",
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.iOS])),
                .linkedFramework("CoreML", .when(platforms: [.iOS])),
                .linkedFramework("Accelerate", .when(platforms: [.iOS])),
                .linkedLibrary("c++"),
                .unsafeFlags(["-ObjC"]),
            ]
        ),
        .target(
            name: "flutter_litert_delegate_symbols",
            dependencies: [
                .target(name: "TensorFlowLiteC"),
                .target(name: "TensorFlowLiteCMetal"),
                .target(name: "TensorFlowLiteCCoreML"),
            ],
            path: "Sources/flutter_litert_delegate_symbols",
            publicHeadersPath: "include"
        ),
        .target(
            name: "flutter_litert_custom_ops",
            dependencies: [
                .target(name: "TensorFlowLiteC"),
            ],
            path: "Sources/flutter_litert_custom_ops",
            publicHeadersPath: "include"
        )
    ]
)
