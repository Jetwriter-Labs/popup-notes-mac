// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PopupNotesCore",
    platforms: [.macOS(.v14)], // Observation requires macOS 14+; app deploys to macOS 15.
    products: [
        .library(name: "PopupNotesCore", targets: ["PopupNotesCore"]),
    ],
    targets: [
        .target(name: "PopupNotesCore"),
        .testTarget(name: "PopupNotesCoreTests", dependencies: ["PopupNotesCore"]),
    ]
)
