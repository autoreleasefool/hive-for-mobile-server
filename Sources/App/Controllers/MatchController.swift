import Vapor
import Fluent
import FluentSQLite
import Crypto

final class MatchController {
	func create(_ request: Request) throws -> Future<Match> {
		let user = try request.requireAuthenticated(User.self)
		let match = try Match(withHost: user)
		return match.save(on: request)
	}

	func details(_ request: Request) throws -> Future<MatchDetailsResponse> {
		try request.parameters.next(Match.self)
			.flatMap {
				User.query(on: request)
					.filter(\.id ~~ [$0.hostId, $0.opponentId])
					.all()
					.and(result: $0)
			}.map { users, match in
				var response = try MatchDetailsResponse(from: match)
				for user in users {
					if user.id == match.hostId {
						response.host = try UserSummaryResponse(from: user)
					} else if user.id == match.opponentId {
						response.opponent = try UserSummaryResponse(from: user)
					}
				}
				return response
			}
	}

	func openMatches(_ request: Request) throws -> Future<[MatchDetailsResponse]> {
		Match.query(on: request)
			.filter(\.status == .open)
			.join(\User.id, to: \Match.hostId)
			.alsoDecode(User.self)
			.join(\User.id, to: \Match.opponentId, method: .left)
			.alsoDecode(User.OptionalFields.self, User.name)
			.sort(\Match.createdAt)
			.all()
			.map { try $0.map { (matchAndHost, opponent) in
				let (match, host) = matchAndHost
				var response = try MatchDetailsResponse(from: match)
				response.host = try UserSummaryResponse(from: host)
				response.opponent = try UserSummaryResponse(from: User(opponent))
				return response
			}}
	}

	func spectatableMatches(_ request: Request) throws -> Future<[MatchDetailsResponse]> {
		Match.query(on: request)
			.filter(\.status ~~ [.active, .notStarted])
			.sort(\.createdAt)
			.all()
			.map { try $0.map { try MatchDetailsResponse(from: $0) } }
	}

	func joinMatch(_ request: Request) throws -> Future<MatchDetailsResponse> {
		let user = try request.requireAuthenticated(User.self)
		return try request.parameters.next(Match.self)
			.flatMap { match in
				guard match.opponentId == nil else {
					throw Abort(.badRequest, reason: "Match is already filled")
				}

				guard match.hostId != user.id else {
					throw Abort(.badRequest, reason: "Cannot join a match you are hosting")
				}

				return try match.addOpponent(user.requireID(), on: request)
					.map { try MatchDetailsResponse(from: $0) }
			}
	}
}

// MARK: RouteCollection

extension MatchController: RouteCollection {
	func boot(router: Router) throws {
		let matchGroup = router.grouped("matches")

		// Public routes
		matchGroup.get("open", use: openMatches)
		matchGroup.get("spectatable", use: spectatableMatches)
		matchGroup.get(Match.parameter, use: details)

		// Token authenticated routes
		let tokenMatchGroup = matchGroup.grouped(User.tokenAuthMiddleware())
		tokenMatchGroup.post(Match.parameter, "join", use: joinMatch)
		tokenMatchGroup.post("new", use: create)
	}
}
