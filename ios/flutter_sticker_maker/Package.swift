// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_sticker_maker",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(
            name: "flutter-sticker-maker",
            targets: ["flutter_sticker_maker", "flutter_sticker_maker_c"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_sticker_maker",
            dependencies: [
                "flutter_sticker_maker_c",
                .product(name: "FlutterFramework", package: "FlutterFramework")
                ],
            resources: [
                .process("textSpeckle_Normal.png")
            ]
        ),
        .target(
            name: "flutter_sticker_maker_c",
            dependencies: [],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include/flutter_sticker_maker_c")
            ]
        )
    ]
)