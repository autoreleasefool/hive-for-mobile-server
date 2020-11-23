//
//  SupportedVersionMiddleware.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-11-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Regex
import Vapor

final class SupportedVersionMiddleware: Middleware {

	private static let minSupportedVersion = SemVer(
		majorVersion: 1,
		minorVersion: 0,
		patchVersion: 0,
		preRelease: nil,
		build: nil
	)

	private static let userAgentVersionRegex = Regex(#"^Hive for (iOS|Android)/(iOS|Android)/(.*)$"#)

	func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		do {
			guard let userAgent = req.headers.first(name: .userAgent) else {
				throw Abort(.badRequest, reason: "User-Agent not available")
			}

			guard let match = Self.userAgentVersionRegex.firstMatch(in: userAgent),
						match.captures.count > 2,
						let rawVersionString = match.captures[2] else {
				throw Abort(.badRequest, reason: "User-Agent does not match expected pattern")
			}

			let version: SemVer?
			do {
				version = try SemVer(rawValue: rawVersionString)
			} catch {
				throw Abort(.badRequest, reason: "User-Agent version does not match expected pattern: \(error)")
			}

			guard let requestVersion = version, requestVersion >= Self.minSupportedVersion else {
				throw Abort(.imATeapot, reason: "Version `\(version?.description ?? "null")` is not supported")
			}

			return next.respond(to: req)
		} catch {
			return req.eventLoop.makeFailedFuture(error)
		}
	}
}
