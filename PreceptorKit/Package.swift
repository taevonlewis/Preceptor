// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "PreceptorKit",
    // Match the app's existing floors; SwiftData remains in PreceptorStore.
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "PreceptorCore", targets: ["PreceptorCore"]),
        .library(name: "PreceptorExtract", targets: ["PreceptorExtract"]),
        .library(name: "PreceptorGenerate", targets: ["PreceptorGenerate"]),
        .library(name: "PreceptorStore", targets: ["PreceptorStore"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "PreceptorCore",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .target(name: "PreceptorExtract", dependencies: ["PreceptorCore"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .target(name: "PreceptorGenerate", dependencies: ["PreceptorCore"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .target(name: "PreceptorStore", dependencies: ["PreceptorCore"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .testTarget(name: "PreceptorCoreTests", dependencies: ["PreceptorCore", "PreceptorGenerate"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .testTarget(name: "PreceptorExtractTests", dependencies: ["PreceptorCore", "PreceptorExtract"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .testTarget(name: "PreceptorStoreTests", dependencies: ["PreceptorCore", "PreceptorExtract", "PreceptorStore"],
            resources: [.copy("Fixtures/OriginalAssets")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .testTarget(name: "PreceptorIntegrationTests",
            dependencies: ["PreceptorCore", "PreceptorExtract", "PreceptorGenerate", "PreceptorStore"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
    ])
