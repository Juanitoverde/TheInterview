// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InterviewCore",
    platforms: [
        .visionOS(.v1),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "InterviewCore", targets: ["InterviewCore"]),
    ],
    targets: [
        .target(name: "InterviewCore"),
        .testTarget(name: "InterviewCoreTests", dependencies: ["InterviewCore"]),
    ]
)
