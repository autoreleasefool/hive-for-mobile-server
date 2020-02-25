import Vapor
import Regex
import HiveEngine

extension WSClientMessage {
	static func extractMovement(from string: String) throws -> RelativeMovement {
		guard let moveStart = string.firstIndex(of: " "),
			let movement = RelativeMovement(notation: String(string[moveStart...]).trimmingCharacters(in: .whitespaces)) else {
			throw WSServerResponseError.invalidCommand
		}

		return movement
	}

	static func handle(movement: RelativeMovement, with context: WSClientMessageContext) throws {
		guard let matchContext = context as? WSClientMatchContext else {
			throw WSServerResponseError.invalidCommand
		}

		try MatchPlayController.shared.play(movement: movement, with: matchContext)
	}
}
