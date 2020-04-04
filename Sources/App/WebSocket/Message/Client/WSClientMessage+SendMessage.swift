//
//  WSClientMessage+SendMessage.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

extension WSClientMessage {
	static func extractMessage(from string: String) throws -> String {
		guard let messageStart = string.firstIndex(of: " ") else {
			throw WSServerResponseError.invalidCommand
		}

		return String(string[messageStart...]).trimmingCharacters(in: .whitespaces)
	}

	static func handle(message: String, with context: WSClientMessageContext) throws {
		context.userWS.webSocket.send(response: .message(context.user, message))
		context.opponentWS?.webSocket.send(response: .message(context.user, message))
	}
}
