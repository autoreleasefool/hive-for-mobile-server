import Vapor

public func routes(_ router: Router) throws {
	router.get { req in
		"It works!"
	}

	let apiRouter = router.grouped("api")
	try apiRouter.register(collection: UserController())
	try apiRouter.register(collection: MatchController())
}
