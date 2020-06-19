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

// func sockets(_ wss: NIOWebSocketServer) {
// 	let responder = WebSocketResponder(
// 		shouldUpgrade: { _ in return [:] },
// 		onUpgrade: { ws, req in
// 			WebSocketAuthenticationMiddleware.handle(
// 				webSocket: ws,
// 				request: req,
// 				handler: gameManager.joinMatch
// 			)
// 		}
// 	)
// 	let route: Route<WebSocketResponder> = .init(path: [Match.parameter, "play"], output: responder)
// 	wss.register(route: route)
// }
