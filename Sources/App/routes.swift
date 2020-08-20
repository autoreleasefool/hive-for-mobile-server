//
//  routes.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

 let gameManager = GameManager()

func routes(_ app: Application) throws {
	app.get { _ in
		"It works!"
	}

	try app.register(collection: UserController())
	try app.register(collection: MatchController(gameManager: gameManager))
}

func socketRoutes(_ app: Application) {
	let tokenProtected = app.grouped(Token.authenticator())
		.grouped(Token.guardMiddleware())

	tokenProtected.webSocket(.parameter(MatchController.Parameter.match.rawValue), "play") { req, ws in
		guard let user = try? req.auth.require(User.self), let userId = user.id else {
			_ = ws.close(code: .policyViolation)
			return
		}

		do {
			try gameManager.joinMatch(on: req, ws: ws, user: user)
		} catch {
			ws.send(error: .unknownError(error), fromUser: userId)
			_ = ws.close(code: .unexpectedServerError)
			print("Error joining match: \(error)")
		}
	}

	tokenProtected.webSocket(.parameter(MatchController.Parameter.match.rawValue), "spectate") { req, ws in
		guard let user = try? req.auth.require(User.self), let userId = user.id else {
			_ = ws.close(code: .policyViolation)
			return
		}

		do {
			try gameManager.spectateMatch(on: req, ws: ws, user: user)
		} catch {
			ws.send(error: .unknownError(error), fromUser: userId)
			_ = ws.close(code: .unexpectedServerError)
			print("Error adding spectator: \(error)")
		}
	}
}
