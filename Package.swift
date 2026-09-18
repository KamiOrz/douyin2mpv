// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Douyin2MPV",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Douyin2MPV", targets: ["Douyin2MPV"]), .library(name: "DouyinCore", targets: ["DouyinCore"])],
    targets: [.target(name: "DouyinCore"), .executableTarget(name: "Douyin2MPV", dependencies: ["DouyinCore"]), .testTarget(name: "DouyinCoreTests", dependencies: ["DouyinCore"])]
)
