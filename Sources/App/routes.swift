//
//  routes.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

func RESTRoutes(_ router: Router) throws {
	router.get { _ in
		"It works!"
	}

	let apiRouter = router.grouped("api")
	try apiRouter.register(collection: UserController())
	try apiRouter.register(collection: MatchController())
}

func webSocketRoutes(_ wss: NIOWebSocketServer) {
	let responder = WebSocketResponder(
		shouldUpgrade: { _ in return [:] },
		onUpgrade: { ws, req in
			WebSocketAuthenticationMiddleware.handle(
				webSocket: ws,
				request: req,
				handler: LobbyController.shared.onJoinLobbyMatch
			)
		}
	)
	let route: Route<WebSocketResponder> = .init(path: [Match.parameter, "play"], output: responder)
	wss.register(route: route)
}
