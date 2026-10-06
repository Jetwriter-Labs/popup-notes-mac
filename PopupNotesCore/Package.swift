// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PopupNotesCore",
    platforms: [.macOS(.v14)], // SwiftData requires macOS 14+; the app deploys to macOS 15.6.
    products: [
        .library(name: "PopupNotesCore", targets: ["PopupNotesCore"]),
    ],
    targets: [
        // MemberImportVisibility matches the app target: each file imports what it uses.
        .target(name: "PopupNotesCore",
                swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]),
        .testTarget(name: "PopupNotesCoreTests", dependencies: ["PopupNotesCore"],
                    swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]),
    ]
)
