import Vapor

class MatchPlayManager {

	static let shared = MatchPlayManager()

	private init() { }

	private var matchCache: [Match.ID: Match] = [:]

	func onInitialize(_ ws: WebSocket, _ request: Request, _ user: User) throws {
		guard let rawMatchId = request.parameters.rawValues(for: Match.self).first,
			let matchId = UUID(rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined")
		}

		guard let match = matchCache[matchId] else {
			throw Abort(.badRequest, reason: #"Match with ID "\#(matchId)" could not be found"#)
		}

		

		#warning("TODO: handle ws text")
	}
}

// MARK: - REST

extension MatchPlayManager {
	func begin(match: Match, on conn: DatabaseConnectable) throws -> Future<Match> {
		let matchId = try match.requireID()
		guard matchCache[matchId] == nil else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" already in progress"#)
		}

		return try match.begin(on: conn)
			.map { [unowned self] match in
				self.matchCache[matchId] = match
				return match
			}
	}

	func add(opponent: User.ID, to matchId: Match.ID, on conn: DatabaseConnectable) throws -> Future<JoinMatchResponse> {
		guard let match = matchCache[matchId] else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard match.opponentId == nil else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is full"#)
		}

		guard match.hostId != opponent else {
			throw Abort(.badRequest, reason: "Cannot join a match you are hosting")
		}

		return match.addOpponent(opponent, on: conn)
			.map { try JoinMatchResponse(from: $0) }
	}
}

// MARK: - Routes

extension MatchPlayManager {
	func registerRoutes(to wss: NIOWebSocketServer) {
		let responder = WebSocketResponder(
			shouldUpgrade: { _ in return [:] },
			onUpgrade: { [unowned self] ws, req in
				WebSocketAuthenticationMiddleware.handle(
					webSocket: ws,
					request: req,
					handler: self.onInitialize
				)
			}
		)
		let route: Route<WebSocketResponder> = .init(path: [Match.parameter, "play"], output: responder)
		wss.register(route: route)
	}
}
