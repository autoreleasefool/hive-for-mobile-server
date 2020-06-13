//
//  routes.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

let gameManager = GameManager()

func routes(_ router: Router) throws {
	router.get { _ in
		"It works!"
	}

	let apiRouter = router.grouped("api")
	try apiRouter.register(collection: UserController())
	try apiRouter.register(collection: MatchController(gameManager: gameManager))
}

func sockets(_ wss: NIOWebSocketServer) {
	let responder = WebSocketResponder(
		shouldUpgrade: { _ in return [:] },
		onUpgrade: { ws, req in
			WebSocketAuthenticationMiddleware.handle(
				webSocket: ws,
				request: req,
				handler: gameManager.joinMatch
			)
		}
	)
	let route: Route<WebSocketResponder> = .init(path: [Match.parameter, "play"], output: responder)
	wss.register(route: route)
}
