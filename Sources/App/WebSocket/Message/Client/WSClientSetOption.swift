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
		_ = context.state.set(option: option, to: newValue)
	}
}

extension WSClientSetOption {
	static func canParse(text: String) -> Bool {
		WSClientSetOption.regex.matches(text)
	}
}
