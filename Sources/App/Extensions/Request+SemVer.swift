//
//  Request+SemVer.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-23.
// Copyright © 2020 Joseph Roque. All rights reserved.
//

import Regex
import Vapor

extension Request {
	private static let userAgentAppVersionRegex = Regex(#"^Hive for iOS\+(.*?)(/|$)"#)
	private static let userAgentEngineVersionRegex = Regex(#"HiveEngine\+(.*?)(/|$)"#)

	func appVersion() throws -> SemVer? {
		guard let userAgent = headers.first(name: .userAgent) else {
			throw Abort(.badRequest, reason: "User-Agent not available")
		}

		// If other apps are to be supported, remove this requirement to match the Regex
		guard let match = Self.userAgentAppVersionRegex.firstMatch(in: userAgent),
					match.captures.count >= 1,
					let rawVersionString = match.captures[0] else {
			throw Abort(.badRequest, reason: "User-Agent does not match expected pattern")
		}

		do {
			return try SemVer(rawValue: rawVersionString)
		} catch {
			throw Abort(.badRequest, reason: "User-Agent version does not match expected pattern: \(error)")
		}
	}

	func engineVersion() throws -> SemVer? {
		guard let userAgent = headers.first(name: .userAgent) else {
			throw Abort(.badRequest, reason: "User-Agent not available")
		}

		// If other apps are to be supported, remove this requirement to match the Regex
		guard let match = Self.userAgentEngineVersionRegex.firstMatch(in: userAgent),
					match.captures.count >= 1,
					let rawVersionString = match.captures[0] else {
			throw Abort(.badRequest, reason: "User-Agent does not match expected pattern")
		}

		do {
			return try SemVer(rawValue: rawVersionString)
		} catch {
			throw Abort(.badRequest, reason: "User-Agent version does not match expected pattern: \(error)")
		}
	}
}
