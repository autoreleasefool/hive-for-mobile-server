import Vapor
import HiveEngine

enum WSServerResponse {
	case state(GameState)
//	case startGame
//	case forfeit
//	case message(String)
//	case error(WSServerError)
}

extension WebSocket {
	func send(response: WSServerResponse) {
		switch response {
		case .state(let state):
			self.send("STATE \(state.gameString)")
//		case .startGame:
//			self.send("GLHF")
//		case .forfeit:
//			self.send("FF")
//		case .message(let message):
//			self.send("MSG \(message)")
//		case .error(let error):
//			self.send("ERR \(error.errorDescription)")
		}
	}

	func send(error: WSServerResponseError) {
		self.send("ERR \(error.errorCode) \(error.errorDescription)")
	}
}
