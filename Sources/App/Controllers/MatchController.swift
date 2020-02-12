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

	func details(_ request: Request) throws -> Future<MatchResponse> {
		try request.parameters.next(Match.self)
			.flatMap { match in
				var response = try MatchResponse(from: match)
				return User.query(on: request)
					.filter(\.id ~~ [match.hostId, match.opponentId])
					.all()
					.map {
						try $0.forEach {
							if $0.id == match.hostId {
								response.host = try UserResponse(from: $0)
							} else if $0.id == match.opponentId {
								response.opponent = try UserResponse(from: $0)
							}
						}

						return response
					}
			}
	}

	func openMatches(_ request: Request) throws -> Future<[MatchResponse]> {
		Match.query(on: request)
			.filter(\.rawStatus == MatchStatus.open.rawValue)
			.join(\User.id, to: \Match.hostId)
			.alsoDecode(User.self)
			.join(\User.id, to: \Match.opponentId, method: .left)
			.alsoDecode(User.OptionalFields.self, User.name)
			.sort(\Match.createdAt)
			.all()
			.map { try $0.map { (matchAndHost, opponent) in
				let (match, host) = matchAndHost
				var response = try MatchResponse(from: match)
				response.host = try UserResponse(from: host)
				response.opponent = try UserResponse(from: User(opponent))
				return response
			}}
	}

	func spectatableMatches(_ request: Request) throws -> Future<[MatchResponse]> {
		Match.query(on: request)
			.filter(\.rawStatus ~~ [MatchStatus.active.rawValue, MatchStatus.notStarted.rawValue])
			.sort(\.createdAt)
			.all()
			.map { try $0.map { try MatchResponse(from: $0) } }
	}

	func joinMatch(_ request: Request) throws -> Future<Match> {
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
