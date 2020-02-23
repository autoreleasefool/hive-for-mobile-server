import Vapor
import HiveEngine

struct WSClientMessageContext {
	let user: User.ID
	let opponent: User.ID?
	let matchId: Match.ID
	let match: Match
	let state: GameState

	let userWS: WebSocket
	let opponentWS: WebSocket?
}

protocol WSClientMessageHandler {
	func handle(_ context: WSClientMessageContext)
}

func clientMessageHandler(from text: String) -> WSClientMessageHandler? {
	if WSClientSetOption.canParse(text: text) {
		return WSClientSetOption(from: text)
	}

	return nil
}
