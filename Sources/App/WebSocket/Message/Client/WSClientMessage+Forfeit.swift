extension WSClientMessage {
	static func handle(playerForfeit userId: User.ID, with context: WSClientMessageContext) throws {
		guard let matchContext = context as? WSClientMatchContext else {
			return context.userWS.webSocket.send(error: .invalidCommand)
		}

		let promise = try MatchPlayController.shared.forfeitMatch(context: matchContext)

		promise.whenSuccess { match in
			matchContext.userWS.webSocket.send(response: .forfeit(context.user))
			matchContext.requiredOpponentWS.webSocket.send(response: .forfeit(context.user))
		}

		promise.whenFailure { error in
			MatchPlayController.shared.handle(error: error, on: context.userWS, context: context)
		}
	}
}
