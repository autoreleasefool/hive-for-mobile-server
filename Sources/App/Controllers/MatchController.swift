import Vapor
import FluentSQLite
import Crypto

final class MatchController {
	func create(_ request: Request) throws -> Future<Match> {
		let user = try request.requireAuthenticated(User.self)
		let match = try Match(withHost: user)
		return match.save(on: request)
	}

	func details(_ request: Request) throws -> Future<MatchResponse> {
		try request.parameters.next(Match.self)
			.map { try MatchResponse(from: $0) }
	}

	func openMatches(_ request: Request) throws -> Future<[Match]> {
		return request.eventLoop.newSucceededFuture(result: [])
	}

	func activeMatches(_ request: Request) throws -> Future<[Match]> {
		return request.eventLoop.newSucceededFuture(result: [])
	}

	func joinMatch(_ request: Request) throws -> Future<HTTPResponseStatus> {
		return request.eventLoop.newSucceededFuture(result: .ok)
	}

	func leaveMatch(_ request: Request) throws -> Future<HTTPResponseStatus> {
		return request.eventLoop.newSucceededFuture(result: .ok)
	}
}

// MARK: RouteCollection

extension MatchController: RouteCollection {
	func boot(router: Router) throws {
		let matchGroup = router.grouped("matches")

		// Public routes
		matchGroup.get(Match.parameter, "open", use: openMatches)
		matchGroup.get(Match.parameter, "summary", use: activeMatches)
		matchGroup.get(Match.parameter, use: details)

		// Token authenticated routes
		let tokenMatchGroup = matchGroup.grouped(User.tokenAuthMiddleware())
		tokenMatchGroup.post(Match.parameter, "join", use: joinMatch)
		tokenMatchGroup.post(Match.parameter, "leave", use: leaveMatch)
		tokenMatchGroup.post("new", use: create)
	}
}
