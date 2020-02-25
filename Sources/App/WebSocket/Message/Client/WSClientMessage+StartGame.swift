extension WSClientMessage {
	static func handle(playerReady: User.ID, with context: WSClientMessageContext) throws {
		guard let lobbyContext = context as? WSClientLobbyContext else {
			return context.userWS.webSocket.send(error: .invalidCommand)
		}

		try LobbyController.shared.readyPlayer(lobbyContext)
	}
}
