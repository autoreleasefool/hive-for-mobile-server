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
		guard let user = try? req.auth.require(User.self) else {
			return
		}

		try? gameManager.joinMatch(on: req, ws: ws, user: user)
	}
}
