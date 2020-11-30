//
//  routes.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

func routes(_ app: Application) throws {
	app.get { _ in
		"It works!"
	}

	try app.register(collection: UserController())
	try app.register(collection: MatchController())
}

func socketRoutes(_ app: Application) {
	let tokenProtected = app.grouped(Token.authenticator())
		.grouped(Token.guardMiddleware())

	tokenProtected.webSocket("play", .parameter(MatchController.Parameter.match.rawValue)) { req, ws in
		app.logger.debug("Handling request to play")
		guard let user = try? req.auth.require(User.self), let userId = user.id else {
			_ = ws.close(code: .policyViolation)
			return
		}

		do {
			try app.gameService.connectPlayer(user, ws: ws, on: req)
		} catch {
			ws.send(error: .unknownError(error), fromUser: userId)
			_ = ws.close(code: .unexpectedServerError)
			app.logger.error("Error joining match: \(error)")
		}
	}

	tokenProtected.webSocket("spectate", .parameter(MatchController.Parameter.match.rawValue)) { req, ws in
		app.logger.debug("Handling request to spectate")
		guard let user = try? req.auth.require(User.self), let userId = user.id else {
			_ = ws.close(code: .policyViolation)
			return
		}

		do {
			try app.gameService.connectSpectator(user, ws: ws, on: req)
		} catch {
			ws.send(error: .unknownError(error), fromUser: userId)
			_ = ws.close(code: .unexpectedServerError)
			app.logger.error("Error adding spectator: \(error)")
		}
	}
}
