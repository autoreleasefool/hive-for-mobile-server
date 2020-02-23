import Vapor
import HiveEngine

class MatchPlayManager {

	static let shared = MatchPlayManager()

	private init() { }

	private var matchCache: [Match.ID: Match] = [:]
	private var matchGameState: [Match.ID: GameState] = [:]
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

			guard let state = self.matchGameState[matchId] else {
				self.handle(error: Abort(.badRequest, reason: #"Could not find GameState in match "\#(matchId)""#), on: ws)
				return
			}

			let opponentId = match.otherPlayer(from: userId)
			let opponentWS: WebSocket?
			if let opponentId = opponentId {
				opponentWS = self.connections[opponentId]
			} else {
				opponentWS = nil
			}

			let context = WSClientMatchContext(user: userId, opponent: opponentId, matchId: matchId, match: match, userWS: ws, opponentWS: opponentWS, state: state)
			self.handle(text: text, context: context)
		}

		// Remove the connection when the WebSocket closes
		ws.onClose.whenComplete { [unowned self] in
			self.connections[userId] = nil
		}
	}

	private func handle(error: Error, on ws: WebSocket) {

	}

	private func handle(text: String, context: WSClientMatchContext) {
		let handler = clientMessageHandler(from: text)
		handler?.handle(context)
	}
}

// MARK: - Message Context

class WSClientMatchContext: WSClientMessageContext {
	let user: User.ID
	let opponent: User.ID?
	let matchId: Match.ID
	let match: Match

	let userWS: WebSocket
	let opponentWS: WebSocket?

	let state: GameState

	init(user: User.ID, opponent: User.ID?, matchId: Match.ID, match: Match, userWS: WebSocket, opponentWS: WebSocket?, state: GameState) {
		self.user = user
		self.opponent = opponent
		self.matchId = matchId
		self.match = match
		self.userWS = userWS
		self.opponentWS = opponentWS
		self.state = state
	}
}

extension MatchPlayManager {
	func beginMatch(context: WSClientMessageContext) {
		
	}
}
