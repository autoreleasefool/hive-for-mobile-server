// swift-tools-version:5.2
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
		.package(name: "Auth", url: "https://github.com/vapor/auth.git", from: "2.0.4"),
		.package(name: "Vapor", url: "https://github.com/vapor/vapor.git", from: "3.3.1"),
		.package(name: "FluentSQLite", url: "https://github.com/vapor/fluent-sqlite.git", from: "3.0.0"),
		.package(name: "HiveEngine", url: "https://github.com/josephroquedev/hive-engine.git", from: "3.0.0"),
	],
	targets: [
		.target(
			name: "App",
			dependencies: [
				.product(name: "Authentication", package: "Auth"),
				.product(name: "FluentSQLite", package: "FluentSQLite"),
				.product(name: "Vapor", package: "Vapor"),
				.product(name: "HiveEngine", package: "HiveEngine"),
			]
		),
		.target(name: "Run", dependencies: ["App"]),
		.testTarget(name: "AppTests", dependencies: ["App"]),
	]
)
