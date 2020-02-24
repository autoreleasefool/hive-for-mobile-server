extension WSClientMessage {
	static func extractMessage(from string: String) throws -> String {
		guard let messageStart = string.firstIndex(of: " ") else {
			throw WSServerResponseError.invalidCommand
		}

		return String(string[messageStart...]).trimmingCharacters(in: .whitespaces)
	}

	static func handle(message: String, with context: WSClientMessageContext) throws {
		context.userWS.send(response: .message(context.user, message))
		context.opponentWS?.send(response: .message(context.user, message))
	}
}
