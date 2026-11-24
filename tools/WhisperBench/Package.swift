// swift-tools-version: 6.2
// Evaluation bench: runs the app's own Whisper pipeline on a local audio file
// and writes eval_report.md. Not part of the app; see README.md.
import PackageDescription

let package = Package(
    name: "WhisperBench",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Same pinned revision as Transcriber.xcodeproj.
        .package(url: "https://github.com/argmaxinc/WhisperKit", revision: "ba094495e40ff255f30ca4602e2c75994f255df7")
    ],
    targets: [
        .executableTarget(
            name: "WhisperBench",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            swiftSettings: [   // match the app target
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        )
    ]
)
