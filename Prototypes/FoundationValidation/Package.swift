// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FoundationValidation",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "ValidationCore", targets: ["ValidationCore"]), .executable(name: "hhos-validation", targets: ["ValidationCLI"])],
    targets: [.target(name: "ValidationCore"), .executableTarget(name: "ValidationCLI", dependencies: ["ValidationCore"]), .testTarget(name: "ValidationCoreTests", dependencies: ["ValidationCore"])]
)
