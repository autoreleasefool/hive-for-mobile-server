import Vapor
import HiveEngine

class MatchPlayController {

	static let shared = MatchPlayController()

	private init() { }

	private var inProgressMatches: [Match.ID: Match] = [:]
	private var matchGameStates: [Match.ID: GameState] = [:]
	private var connections: [User.ID: WebSocket] = [:]

	func startGamePlay(match: Match, userId: User.ID, ws: WebSocket) throws {
		let matchId = try match.requireID()
		connections[userId] = ws

		#warning("TODO: need to keep clients in sync when one disconnects or encounters error")

		ws.onText { [unowned self] ws, text in
			guard let opponentId = match.otherPlayer(from: userId),
				let opponentWS = self.connections[opponentId] else {
				return self.handle(
					error: Abort(.internalServerError, reason: #"Opponent in match "\#(matchId)" could not be found"#),
					on: ws,
					context: nil
				)
			}

			guard let state = self.matchGameStates[matchId] else {
				return self.handle(
					error: Abort(.internalServerError, reason: #"GameState for match "\#(matchId)" could not be found"#),
					on: ws,
					context: nil
				)
			}

			let context = WSClientMatchContext(user: userId, opponent: opponentId, matchId: matchId, match: match, userWS: ws, opponentWS: opponentWS, state: state)
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

	private func handle(text: String, context: WSClientMatchContext) {
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

class WSClientMatchContext: WSClientMessageContext {
	let user: User.ID
	let opponent: User.ID?
	let requiredOpponent: User.ID
	let matchId: Match.ID
	let match: Match

	let userWS: WebSocket
	let opponentWS: WebSocket?
	let requiredOpponentWS: WebSocket

	let state: GameState

	init(user: User.ID, opponent: User.ID, matchId: Match.ID, match: Match, userWS: WebSocket, opponentWS: WebSocket, state: GameState) {
		self.user = user
		self.opponent = opponent
		self.requiredOpponent = opponent
		self.matchId = matchId
		self.match = match
		self.userWS = userWS
		self.opponentWS = opponentWS
		self.requiredOpponentWS = opponentWS
		self.state = state
	}
}

extension MatchPlayController {
	func beginMatch(context: WSClientLobbyContext) throws {
		guard let opponent = context.opponent,
			let opponentWS = context.opponentWS else {
			throw Abort(.internalServerError, reason: #"Cannot begin match "\#(context.matchId)" without opponent"#)
		}

		inProgressMatches[context.matchId] = context.match
		matchGameStates[context.matchId] = context.gameState
		try startGamePlay(match: context.match, userId: context.user, ws: context.userWS)
		try startGamePlay(match: context.match, userId: opponent, ws: opponentWS)
	}
}
