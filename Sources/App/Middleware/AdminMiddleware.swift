//
//  AdminMiddleware.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

final class AdminMiddleware: Middleware {
	func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		let user = try req.auth.require(User.self)

		guard user.isAdmin else {
			throw Abort(.unauthorized)
		}

		return try next.respond(to: req)
	}
}
