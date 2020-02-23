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
		if let lobbyContext = context as? WSClientLobbyContext {
			lobbyContext.options.set(option, to: newValue)

			context.userWS.send(response: .setOption(option, newValue))
			context.opponentWS?.send(response: .setOption(option, newValue))
		} else {
			self.handleFailure(context: context)
		}
	}

	private func handleFailure(context: WSClientMessageContext) {
		if context is WSClientLobbyContext {
			// Should be able to set option in lobby, so an error must have occurred
			context.userWS.send(error: .optionValueNotUpdated(option, String(newValue)))
		} else {
			// Cannot change options at any other time, so client is issuing bad commands
			context.userWS.send(error: .optionNonModifiable)
		}
	}
}

extension WSClientSetOption {
	static func canParse(text: String) -> Bool {
		WSClientSetOption.regex.matches(text)
	}
}
