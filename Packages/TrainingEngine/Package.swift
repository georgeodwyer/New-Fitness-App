// swift-tools-version:5.9
import PackageDescription

// TrainingEngine: the training "brain" of Kinetix (plan generation, progression, pace
// targets, load and balancing).
// KinetixSync: talks to Supabase (auth + last-write-wins record sync).
// Both are Foundation-only, so they're unit-tested on Linux and macOS and can be reused
// by a future Apple Watch app.
let package = Package(
    name: "TrainingEngine",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "TrainingEngine", targets: ["TrainingEngine"]),
        .library(name: "KinetixSync", targets: ["KinetixSync"])
    ],
    targets: [
        .target(
            name: "TrainingEngine",
            resources: [.process("Resources")]
        ),
        .target(name: "KinetixSync"),
        .testTarget(name: "TrainingEngineTests", dependencies: ["TrainingEngine"]),
        .testTarget(name: "KinetixSyncTests", dependencies: ["KinetixSync"])
    ]
)
