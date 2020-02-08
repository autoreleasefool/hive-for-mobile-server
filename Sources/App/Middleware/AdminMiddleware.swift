import Vapor

final class AdminMiddleware: Middleware {
	func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
		let user = try request.requireAuthenticated(User.self)

		guard user.isAdmin else {
			throw Abort(.unauthorized)
		}

		return try next.respond(to: request)
	}
}
