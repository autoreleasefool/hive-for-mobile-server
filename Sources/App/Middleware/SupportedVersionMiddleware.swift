//
//  SupportedVersionMiddleware.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-11-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Regex
import Vapor

class SupportedVersionMiddleware: Middleware {
	private let name: String
	private let minSupportedVersion: SemVer
	private let versionExtractor: (Request) throws -> SemVer?

	init(
		name: String,
		minSupportedVersion: SemVer,
		versionExtractor: @escaping (Request) throws -> SemVer?
	) {
		self.name = name
		self.minSupportedVersion = minSupportedVersion
		self.versionExtractor = versionExtractor
	}

	func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		do {
			let version = try versionExtractor(req)

			guard let requestVersion = version, requestVersion >= minSupportedVersion else {
				throw Abort(.imATeapot, reason: "\(name) version `\(version?.description ?? "null")` is not supported")
			}

			return next.respond(to: req)
		} catch {
			return req.eventLoop.makeFailedFuture(error)
		}
	}
}

final class SupportedAppVersionMiddleware: SupportedVersionMiddleware {
	private static let userAgentVersionRegex = Regex(#"^Hive for iOS\+(.*?)(/|$)"#)

	init() {
		super.init(
			name: "Hive for iOS",
			minSupportedVersion: SemVer(majorVersion: 1, minorVersion: 0, patchVersion: 0),
			versionExtractor: { req in try req.appVersion() }
		)
	}
}

final class SupportedEngineVersionMiddleware: SupportedVersionMiddleware {
	private static let userAgentVersionRegex = Regex(#"HiveEngine\+(.*?)(/|$)"#)

	init() {
		super.init(
			name: "HiveEngine",
			minSupportedVersion: SemVer(majorVersion: 3, minorVersion: 1, patchVersion: 2),
			versionExtractor: { req in try req.engineVersion() }
		)
	}
}
