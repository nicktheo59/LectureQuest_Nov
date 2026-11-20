// swift-tools-version:5.9
// LectureQuest for macOS — a native SwiftUI port of the web app that runs fully locally.
// Open in Xcode with `open Package.swift`, or run from Terminal with `swift run`.
import PackageDescription

let package = Package(
    name: "LectureQuestMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LectureQuest", targets: ["LectureQuestMac"]),
    ],
    targets: [
        .executableTarget(
            name: "LectureQuestMac",
            path: "Sources/LectureQuestMac"
        ),
        .testTarget(
            name: "LectureQuestMacTests",
            dependencies: ["LectureQuestMac"],
            path: "Tests/LectureQuestMacTests"
        ),
    ]
)
