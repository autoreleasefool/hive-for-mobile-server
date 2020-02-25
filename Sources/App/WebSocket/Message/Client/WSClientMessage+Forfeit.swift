extension WSClientMessage {
	static func handle(playerForfeit userId: User.ID, with context: WSClientMessageContext) throws {
		guard let matchContext = context as? WSClientMatchContext else {
			return context.userWS.webSocket.send(error: .invalidCommand)
		}

		try MatchPlayController.shared.forfeitMatch(context: matchContext)
	}
}
