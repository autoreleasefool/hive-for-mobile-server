import Vapor
import Regex
import HiveEngine

struct WSClientPlayMove: WSClientMessageHandler {
	let movement: RelativeMovement

	init?(from: String) {
		guard let moveStart = from.firstIndex(of: " "),
			let movement = RelativeMovement(notation: String(from[moveStart...])) else {
			return nil
		}

		self.movement = movement
	}

	func handle(_ context: WSClientMessageContext) throws {
		guard let matchContext = context as? WSClientMatchContext else {
			throw WSServerResponseError.invalidCommand
		}

		guard matchContext.state.apply(relativeMovement: movement) else {
			throw WSServerResponseError.invalidMovement(movement.notation)
		}

		context.userWS.send(response: .state(matchContext.state))
		context.opponentWS?.send(response: .state(matchContext.state))
	}
}

extension WSClientPlayMove {
	static func canParse(text: String) -> Bool {
		text.starts(with: "MOV ")
	}
}
