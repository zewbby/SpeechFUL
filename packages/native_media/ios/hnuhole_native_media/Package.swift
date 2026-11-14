// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hnuhole_native_media",
    platforms: [.iOS("15.0")],
    products: [.library(name: "hnuhole-native-media", targets: ["hnuhole_native_media"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [.target(name: "hnuhole_native_media", dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
    ], linkerSettings: [.linkedFramework("Photos"), .linkedFramework("PhotosUI")])]
)
