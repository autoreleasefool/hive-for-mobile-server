import Vapor
import HiveEngine

class LobbyController {

	static let shared = LobbyController()

	private init() { }

	private var lobbyMatches: [Match.ID: Match] = [:]
	private var matchOptions: [Match.ID: Set<GameState.Option>] = [:]
	private var connections: [User.ID: WebSocket] = [:]
	private var readyUsers: Set<User.ID> = []

	func onJoinLobbyMatch(_ ws: WebSocket, _ request: Request, _ user: User) throws {
		let userId = try user.requireID()
		connections[userId] = ws

		guard let rawMatchId = request.parameters.rawValues(for: Match.self).first,
			let matchId = UUID(rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined")
		}

		guard lobbyMatches[matchId] != nil else {
			throw Abort(.badRequest, reason: #"Match with ID "\#(matchId)" could not be found"#)
		}

		#warning("TODO: need to keep clients in sync when one disconnects or encounters error")

		ws.onText { [unowned self] ws, text in
			guard let match = self.lobbyMatches[matchId] else {
				return self.handle(
					error: Abort(.badRequest, reason: #"Match with ID "\#(matchId)" could not be found"#),
					on: ws,
					context: nil
				)
			}

			guard let options = self.matchOptions[matchId] else {
				return self.handle(
					error: Abort(.badRequest, reason: #"Could not find Set<GameState.Option> for match "\#(matchId)""#),
					on: ws,
					context: nil
				)
			}

			let opponentId = match.otherPlayer(from: userId)
			let opponentWS: WebSocket?
			if let opponentId = opponentId {
				opponentWS = self.connections[opponentId]
			} else {
				opponentWS = nil
			}

			let context = WSClientLobbyContext(user: userId, opponent: opponentId, matchId: matchId, match: match, userWS: ws, opponentWS: opponentWS, options: options)
			self.handle(text: text, context: context)
		}

		// Remove the connection when the WebSocket closes
		ws.onClose.whenComplete { [unowned self] in
			self.connections[userId] = nil
		}
	}

	private func handle(error: Error, on ws: WebSocket, context: WSClientMessageContext?) {
		if let serverError = error as? WSServerResponseError {
			// Error can be gracefully handled
		} else {

		}
	}

	private func handle(text: String, context: WSClientLobbyContext) {
		guard let handler = clientMessageHandler(from: text) else {
			return self.handle(error: WSServerResponseError.invalidCommand, on: context.userWS, context: nil)
		}

		do {
			try handler.handle(context)
		} catch {
			self.handle(error: error, on: context.userWS, context: context)
		}
	}
}

// MARK: - Message Context

class WSClientLobbyContext: WSClientMessageContext {
	let user: User.ID
	let opponent: User.ID?
	let matchId: Match.ID
	let match: Match

	let userWS: WebSocket
	let opponentWS: WebSocket?

	var options: Set<GameState.Option>

	var gameState: GameState {
		return GameState(options: options)
	}

	init(user: User.ID, opponent: User.ID?, matchId: Match.ID, match: Match, userWS: WebSocket, opponentWS: WebSocket?, options: Set<GameState.Option>) {
		self.user = user
		self.opponent = opponent
		self.matchId = matchId
		self.match = match
		self.userWS = userWS
		self.opponentWS = opponentWS
		self.options = options
	}
}

// MARK: - REST

extension LobbyController {
	func open(match: Match, on conn: DatabaseConnectable) throws -> Future<Match> {
		let matchId = try match.requireID()
		guard lobbyMatches[matchId] == nil else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" already in lobby"#)
		}

		return try match.begin(on: conn)
			.map { [unowned self] match in
				self.lobbyMatches[matchId] = match
				self.matchOptions[matchId] = match.gameOptions
				return match
			}
	}

	func add(opponent: User.ID, to matchId: Match.ID, on conn: DatabaseConnectable) throws -> Future<JoinMatchResponse> {
		guard let match = lobbyMatches[matchId] else {
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

	func readyPlayer(_ context: WSClientLobbyContext) throws {
		if context.opponent != nil {
			readyUsers.set(context.user, to: !readyUsers.contains(context.user))
		}

		let response = WSServerResponse.setPlayerReady(context.user, readyUsers.contains(context.user))
		context.userWS.send(response: response)
		context.opponentWS?.send(response: response)

		if let opponent = context.opponent,
			readyUsers.contains(context.user) && readyUsers.contains(opponent) {
			removeFromLobby(context: context)
			try MatchPlayController.shared.beginMatch(context: context)
		}
	}

	private func removeFromLobby(context: WSClientMessageContext) {
		lobbyMatches[context.matchId] = nil
		matchOptions[context.matchId] = nil
		connections[context.user] = nil
		readyUsers.remove(context.user)
		if let opponent = context.opponent {
			connections[opponent] = nil
			readyUsers.remove(opponent)
		}

	}
}
