import Regex
import HiveEngine

struct WSClientSetOption: WSClientMessageHandler {
	private static let regex = Regex("^SET ([a-zA-Z0-9]+) (false|true)$")

	let option: GameState.Option
	let newValue: Bool

	init?(from: String) {
		guard let match = WSClientSetOption.regex.firstMatch(in: from),
			let option = GameState.Option(rawValue: match.captures[1] ?? ""),
			let value = Bool(match.captures[2] ?? "") else {
			return nil
		}

		self.option = option
		self.newValue = value
	}

	func handle(_ context: WSClientMessageContext) {
		let success = context.state.set(option: option, to: newValue)
		if success {
			context.userWS.send(response: .state(context.state))
			context.opponentWS?.send(response: .state(context.state))
		} else {
			#warning("TODO: send error to client")
		}
	}
}

extension WSClientSetOption {
	static func canParse(text: String) -> Bool {
		WSClientSetOption.regex.matches(text)
	}
}
