// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LectureQuest",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LectureQuest", targets: ["LectureQuest"])],
    targets: [
        .executableTarget(name: "LectureQuest"),
        .testTarget(name: "LectureQuestTests", dependencies: ["LectureQuest"])
    ]
)
