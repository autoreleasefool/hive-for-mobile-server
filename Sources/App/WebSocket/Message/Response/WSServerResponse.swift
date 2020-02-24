import Vapor
import HiveEngine

enum WSServerResponse {
	case state(GameState)
	case setOption(GameState.Option, Bool)
	case setPlayerReady(User.ID, Bool)
	case message(User.ID, String)
//	case startGame
//	case forfeit
//	case error(WSServerError)
}

extension WebSocket {
	func send(response: WSServerResponse) {
		switch response {
		case .state(let state):
			self.send("STATE \(state.gameString)")
		case .setOption(let option, let value):
			self.send("SET \(option) \(value)")
		case .setPlayerReady(let userId, let isReady):
			self.send("READY \(userId) \(isReady)")
		case .message(let userId, let message):
			self.send("MSG \(userId) \(message)")
//		case .startGame:
//			self.send("GLHF")
//		case .forfeit:
//			self.send("FF")
//		case .error(let error):
//			self.send("ERR \(error.errorDescription)")
		}
	}

	func send(error: WSServerResponseError) {
		self.send("ERR \(error.errorCode) \(error.errorDescription)")
	}
}
