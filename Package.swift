// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MediaInfoQuickLook", platforms: [.macOS(.v13)], products: [.executable(name: "MediaInfoQuickLook", targets: ["MediaInfoQuickLook"])], targets: [.target(name: "MediaInfoCore"), .executableTarget(name: "MediaInfoQuickLook", dependencies: ["MediaInfoCore"]), .testTarget(name: "MediaInfoCoreTests", dependencies: ["MediaInfoCore"])])
