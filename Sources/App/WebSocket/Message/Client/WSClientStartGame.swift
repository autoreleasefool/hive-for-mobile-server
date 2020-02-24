struct WSClientStartGame: WSClientMessageHandler {
	func handle(_ context: WSClientMessageContext) throws {
		if let lobbyContext = context as? WSClientLobbyContext {
			// Mark the player as ready in the lobby
			try LobbyController.shared.readyPlayer(lobbyContext)
		} else {
			// Report an invalid command when the match is not in the lobby
			context.userWS.send(error: .invalidCommand)
		}
	}
}

extension WSClientStartGame {
	static func canParse(text: String) -> Bool {
		text == "GLHF"
	}
}
