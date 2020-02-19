import Vapor

struct WebSocketAuthenticationMiddleware {
	static func handle(webSocket: WebSocket, request: Request, handler: @escaping WebSocketAuthenticationResponder.Handler) {
		let authenticationRequiredResponder = WebSocketAuthenticationResponder(webSocket: webSocket, handler: handler)
		let middleware = User.tokenAuthMiddleware()

		do {
			let _ = try middleware.respond(to: request, chainingTo: authenticationRequiredResponder)
		} catch {
			webSocket.close()
		}
	}
}

struct WebSocketAuthenticationResponder: Responder {
	typealias Handler = (WebSocket, Request, User) throws -> ()

	let webSocket: WebSocket
	let handler: Handler

	func respond(to req: Request) throws -> Future<Response> {
		guard let user: User = try? req.requireAuthenticated() else {
			throw Abort(.unauthorized, reason: "Not authorized")
		}

		try handler(webSocket, req, user)
		let response = Response(http: HTTPResponse(status: .accepted), using: req)

		let promise = req.eventLoop.newPromise(Response.self)
		promise.succeed(result: response)
		return promise.futureResult
	}
}
