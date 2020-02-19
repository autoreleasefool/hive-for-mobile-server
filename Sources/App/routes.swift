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
	MatchPlayManager.shared.registerRoutes(to: wss)
}
