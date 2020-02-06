import Vapor

public func routes(_ router: Router) throws {
	router.get { req in
		return "It works!"
	}
}
