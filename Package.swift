// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MicroHttp",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "MicroHttp",
            targets: ["MicroHttp"]),
        .library(
            name: "Prometheus",
            targets: ["Prometheus"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "MicroHttp",
            dependencies: ["NIO", "NIOHTTP1" , "Logging", "NIOExtras", "Metrics" ]),
        .target(
            name: "Prometheus",
            dependencies: ["CoreMetrics", "NIO", "Cmetrics" ]),
        .target(
            name: "Cmetrics",
            dependencies: []),
        .target(
            name: "MicroHttpExample",
            dependencies: ["MicroHttp", "Prometheus", "NIO", "Logging", "Metrics"]),
        .testTarget(
            name: "MicroHttpTests",
            dependencies: ["MicroHttp"]),
    ]
)
