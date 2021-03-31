// swift-tools-version:5.2
import PackageDescription

let package = Package(
	name: "Hive-for-Mobile-Server",
	platforms: [
		.macOS(.v10_15),
	],
	dependencies: [
		.package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
		.package(name: "HiveEngine", url: "https://github.com/autoreleasefool/hive-engine.git", from: "3.1.2"),
	],
	targets: [
		.target(
			name: "App",
			dependencies: [
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
				.product(name: "Vapor", package: "vapor"),
				.product(name: "JWT", package: "jwt"),
				.product(name: "HiveEngine", package: "HiveEngine"),
			],
			swiftSettings: [
				// Enable better optimizations when building in Release configuration. Despite the use of
				// the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
				// builds. See <https://github.com/swift-server/guides#building-for-production> for details.
				.unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
			]
		),
		.target(name: "Run", dependencies: [.target(name: "App")]),
		.testTarget(
			name: "AppTests",
			dependencies: [
				.target(name: "App"),
				.product(name: "XCTVapor", package: "vapor"),
			]
		),
	]
)
