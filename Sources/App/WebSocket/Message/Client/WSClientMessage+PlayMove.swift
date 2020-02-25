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

		guard matchContext.isUserTurn else {
			throw WSServerResponseError.notPlayerTurn
		}

		guard matchContext.state.apply(relativeMovement: movement) else {
			throw WSServerResponseError.invalidMovement(movement.notation)
		}

		let matchMovement = MatchMovement(from: movement, withContext: matchContext)
		let promise = matchMovement.save(on: matchContext.userWS.request)

		promise.whenSuccess { _ in
			matchContext.userWS.webSocket.send(response: .state(matchContext.state))
			matchContext.requiredOpponentWS.webSocket.send(response: .state(matchContext.state))
		}

		promise.whenFailure {
			MatchPlayController.shared.handle(error: $0, on: context.userWS, context: context)
		}
	}
}
