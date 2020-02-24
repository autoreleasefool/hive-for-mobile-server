import Regex
import HiveEngine

struct WSClientSendMessage: WSClientMessageHandler {
	let message: String

	init?(from: String) {
		guard let messageStart = from.firstIndex(of: " ") else {
			return nil
		}

		self.message = String(from[messageStart...])
	}

	func handle(_ context: WSClientMessageContext) throws {
		context.userWS.send(response: .message(context.user, message))
		context.opponentWS?.send(response: .message(context.user, message))
	}
}

extension WSClientSendMessage {
	static func canParse(text: String) -> Bool {
		text.starts(with: "MSG")
	}
}
