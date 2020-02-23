import Regex
import HiveEngine

//struct WSClientStartGame: WSClientMessageHandler {
//	init?(from: String) {
//		guard WSClientStartGame.canParse(text: from) else {
//			return nil
//		}
//	}
//
//	func handle(_ context: WSClientMessageContext) {
//		let success = context.state.set(option: option, to: newValue)
//		if success {
//			context.userWS.send(response: .state(context.state))
//			context.opponentWS?.send(response: .state(context.state))
//		} else {
//			self.handleFailure(context: context)
//		}
//	}
//
//	private func handleFailure(context: WSClientMessageContext) {
//		if context.state.move > 0 || option.isExpansion {
//			context.userWS.send(error: .optionNonModifiable)
//		} else {
//			context.userWS.send(error: .optionValueNotUpdated(option, String(newValue)))
//		}
//	}
//}
//
//extension WSClientStartGame {
//	static func canParse(text: String) -> Bool {
//		text == "GLHF"
//	}
//}
