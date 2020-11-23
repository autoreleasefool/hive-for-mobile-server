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
	private let extractor: (String) throws -> String

	init(name: String, minSupportedVersion: SemVer, versionExtractor: @escaping (String) throws -> String) {
		self.name = name
		self.minSupportedVersion = minSupportedVersion
		self.extractor = versionExtractor
	}

	func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		do {
			guard let userAgent = req.headers.first(name: .userAgent) else {
				throw Abort(.badRequest, reason: "User-Agent not available")
			}

			let rawVersionString = try extractor(userAgent)

			let version: SemVer?
			do {
				version = try SemVer(rawValue: rawVersionString)
			} catch {
				throw Abort(.badRequest, reason: "User-Agent version does not match expected pattern: \(error)")
			}

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
			versionExtractor: { userAgent in
				// If other apps are to be supported, remove this requirement to match the Regex
				guard let match = Self.userAgentVersionRegex.firstMatch(in: userAgent),
							match.captures.count >= 1,
							let rawVersionString = match.captures[0] else {
					throw Abort(.badRequest, reason: "User-Agent does not match expected pattern")
				}

				return rawVersionString
			}
		)
	}
}

final class SupportedEngineVersionMiddleware: SupportedVersionMiddleware {
	private static let userAgentVersionRegex = Regex(#"HiveEngine\+(.*?)(/|$)"#)

	init() {
		super.init(
			name: "HiveEngine",
			minSupportedVersion: SemVer(majorVersion: 3, minorVersion: 1, patchVersion: 2),
			versionExtractor: { userAgent in
				guard let match = Self.userAgentVersionRegex.firstMatch(in: userAgent),
							match.captures.count >= 1,
							let rawVersionString = match.captures[0] else {
					throw Abort(.badRequest, reason: "User-Agent does not match expected pattern")
				}

				return rawVersionString
			}
		)
	}
}
