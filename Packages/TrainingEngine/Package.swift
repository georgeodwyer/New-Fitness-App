// swift-tools-version:5.9
import PackageDescription

// The training "brain" of Kinetix: plan generation, progression, pace targets,
// load and balancing. Foundation only (no UIKit/SwiftUI/SwiftData), so it can be
// unit-tested anywhere and reused by a future Apple Watch app.
let package = Package(
    name: "TrainingEngine",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "TrainingEngine", targets: ["TrainingEngine"])
    ],
    targets: [
        .target(name: "TrainingEngine"),
        .testTarget(name: "TrainingEngineTests", dependencies: ["TrainingEngine"])
    ]
)
