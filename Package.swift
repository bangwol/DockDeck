// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockDeck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DockDeck", targets: ["DockDeck"]),
        .executable(
            name: "dockdeck-claude-bridge", targets: ["DockDeckClaudeBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.20.0")
    ],
    targets: [
        .executableTarget(
            name: "DockDeck",
            dependencies: ["SwiftTerm"],
            path: "Sources/DockDeck"
        ),
        .executableTarget(
            name: "DockDeckClaudeBridge",
            path: "Sources/DockDeckClaudeBridge"
        ),
        .testTarget(
            name: "DockDeckTests",
            dependencies: ["DockDeck", "DockDeckClaudeBridge"],
            path: "Tests/DockDeckTests"
        )
    ]
)
