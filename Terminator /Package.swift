// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Terminator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Terminator", targets: ["Terminator"]),
    ],
    targets: [
        .executableTarget(
            name: "Terminator",
            path: "Sources/Terminator"
        ),
    ]
)
