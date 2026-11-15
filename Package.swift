// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShojiMachines",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "shoji-machines", targets: ["ShojiMachines"])
    ],
    targets: [
        .executableTarget(name: "ShojiMachines", path: "Sources/ShojiMachines")
    ]
)
