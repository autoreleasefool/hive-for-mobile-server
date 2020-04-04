//
//  AdminMiddleware.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

final class AdminMiddleware: Middleware {
	func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
		let user = try request.requireAuthenticated(User.self)

		guard user.isAdmin else {
			throw Abort(.unauthorized)
		}

		return try next.respond(to: request)
	}
}
