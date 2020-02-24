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
	func handle(_ context: WSClientMessageContext) throws
}

func clientMessageHandler(from text: String) -> WSClientMessageHandler? {
	if WSClientSetOption.canParse(text: text) {
		return WSClientSetOption(from: text)
	} else if WSClientStartGame.canParse(text: text) {
		return WSClientStartGame()
	} else if WSClientSendMessage.canParse(text: text) {
		return WSClientSendMessage(from: text)
	} else if WSClientPlayMove.canParse(text: text) {
		return WSClientPlayMove(from: text)
	}

	return nil
}
