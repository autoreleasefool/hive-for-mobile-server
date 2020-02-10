// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "hive-for-ios-server",
    products: [
        .library(name: "hive-for-ios-server", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/auth.git", from: "2.0.4"),
        .package(url: "https://github.com/vapor/vapor.git", from: "3.3.1"),
        .package(url: "https://github.com/vapor/fluent-sqlite.git", from: "3.0.0"),
        .package(url: "https://github.com/josephroquedev/hive-engine.git", from: "2.3.0")
    ],
    targets: [
        .target(name: "App", dependencies: ["Authentication", "FluentSQLite", "Vapor", "HiveEngine"]),
        .target(name: "Run", dependencies: ["App"]),
        .testTarget(name: "AppTests", dependencies: ["App"])
    ]
)

