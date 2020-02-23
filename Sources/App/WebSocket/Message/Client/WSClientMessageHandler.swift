import Vapor
import HiveEngine

protocol WSClientMessageContext: class {
	var user: User.ID { get }
	var opponent: User.ID? { get }
	var matchId: Match.ID { get }
	var match: Match { get }

	var userWS: WebSocket { get }
	var opponentWS: WebSocket? { get }
}

protocol WSClientMessageHandler {
	func handle(_ context: WSClientMessageContext)
}

func clientMessageHandler(from text: String) -> WSClientMessageHandler? {
	if WSClientSetOption.canParse(text: text) {
		return WSClientSetOption(from: text)
	} else if WSClientStartGame.canParse(text: text) {
		return WSClientStartGame()
	}

	return nil
}
