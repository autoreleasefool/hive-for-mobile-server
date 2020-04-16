// swift-tools-version:5.1
import PackageDescription

let package = Package(
	name: "Hive-for-iOS-Server",
	platforms: [
		.macOS(.v10_15),
	],
	products: [
		.library(name: "Hive-for-iOS-Server", targets: ["App"]),
	],
	dependencies: [
		.package(url: "https://github.com/vapor/auth.git", .exact("2.0.4")),
		.package(url: "https://github.com/vapor/vapor.git", .exact("3.3.1")),
		.package(url: "https://github.com/vapor/fluent-sqlite.git", .exact("3.0.0")),
		.package(url: "https://github.com/josephroquedev/hive-engine.git", .exact("2.4.2")),
	],
	targets: [
		.target(name: "App", dependencies: ["Authentication", "FluentSQLite", "Vapor", "HiveEngine"]),
		.target(name: "Run", dependencies: ["App"]),
		.testTarget(name: "AppTests", dependencies: ["App"]),
	]
)
