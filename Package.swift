// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchBuddy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TouchBarPrivate", targets: ["TouchBarPrivate"]),
        .library(name: "TouchBuddyCore", targets: ["TouchBuddyCore"]),
        .executable(name: "TouchBuddy", targets: ["TouchBuddy"]),
        .executable(name: "touchbuddy-hook", targets: ["touchbuddy-hook"]),
        .executable(name: "sprite-gen", targets: ["sprite-gen"]),
    ],
    targets: [
        .target(
            name: "TouchBarPrivate",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .target(name: "TouchBuddyCore"),
        .executableTarget(
            name: "TouchBuddy",
            dependencies: ["TouchBuddyCore", "TouchBarPrivate"]
        ),
        .executableTarget(name: "touchbuddy-hook", dependencies: ["TouchBuddyCore"]),
        .executableTarget(name: "sprite-gen", dependencies: ["TouchBuddyCore"]),
        .testTarget(name: "TouchBuddyCoreTests", dependencies: ["TouchBuddyCore"]),
    ]
)
