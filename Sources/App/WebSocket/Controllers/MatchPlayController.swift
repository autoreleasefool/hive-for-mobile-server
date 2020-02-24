import Vapor
import HiveEngine

class MatchPlayController: WebSocketController {

	static let shared = MatchPlayController()

	private init() { }

	private var inProgressMatches: [Match.ID: Match] = [:]
	private var matchGameStates: [Match.ID: GameState] = [:]
	var activeConnections: [User.ID : WebSocket] = [:]

	func startGamePlay(match: Match, userId: User.ID, ws: WebSocket) throws {
		let matchId = try match.requireID()
		register(connection: ws, to: userId)

		#warning("TODO: need to keep clients in sync when one disconnects or encounters error")

		ws.onText { [unowned self] ws, text in
			guard let opponentId = match.otherPlayer(from: userId),
				let opponentWS = self.activeConnections[opponentId] else {
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

	private var isUserHost: Bool {
		user == match.hostId
	}

	private var isHostTurn: Bool {
		(match.hostIsWhite && state.currentPlayer == .white) ||
			(!match.hostIsWhite && state.currentPlayer == .black)
	}

	var isUserTurn: Bool {
		return (isUserHost && isHostTurn) || (!isUserHost && !isHostTurn)
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
