import Vapor

class MatchPlayManager {

	static let shared = MatchPlayManager()

	private init() { }

	private var matchCache: [Match.ID: Match] = [:]
	private var connections: [User.ID: WebSocket] = [:]

	func onInitialize(_ ws: WebSocket, _ request: Request, _ user: User) throws {
		let userId = try user.requireID()
		connections[userId] = ws

		guard let rawMatchId = request.parameters.rawValues(for: Match.self).first,
			let matchId = UUID(rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined")
		}

		guard matchCache[matchId] != nil else {
			throw Abort(.badRequest, reason: #"Match with ID "\#(matchId)" could not be found"#)
		}

		#warning("TODO: need to keep clients in sync when one disconnects or encounters error")

		ws.onText { [unowned self] ws, text in
			guard let match = self.matchCache[matchId] else {
				self.handle(error: Abort(.badRequest, reason: #"Match with ID "\#(matchId)" could not be found"#), on: ws)
				return
			}

			guard let opponentId = match.otherPlayer(from: userId),
				let opponentWS = self.connections[opponentId] else {
				self.handle(error: Abort(.badRequest, reason: #"Could not find opponent in match \#(matchId)"#), on: ws)
				return
			}

			self.handle(
				text: text,
				ws: ws,
				opponentWS: opponentWS,
				userId: userId,
				match: match
			)
		}

		// Remove the connection when the WebSocket closes
		ws.onClose.whenComplete { [unowned self] in
			self.connections[userId] = nil
		}
	}

	private func handle(error: Error, on ws: WebSocket) {

	}

	private func handle(text: String, ws: WebSocket, opponentWS: WebSocket, userId: User.ID, match: Match) {
		
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
