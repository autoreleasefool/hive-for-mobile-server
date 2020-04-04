//
//  WSClientMessage+SetOption.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import HiveEngine

extension WSClientMessage {
	static func extractOption(from string: String) throws -> GameState.Option {
		guard let optionStart = string.firstIndex(of: " "),
			let optionEnd = string.lastIndex(of: " "),
			let option = GameState.Option(
				rawValue: String(string[optionStart...optionEnd]).trimmingCharacters(in: .whitespaces)
			) else {
			throw WSServerResponseError.invalidCommand
		}

		return option
	}

	static func extractOptionValue(from string: String) throws -> Bool {
		guard let valueStart = string.lastIndex(of: " "),
			let value = Bool(String(string[valueStart...]).trimmingCharacters(in: .whitespaces)) else {
				throw WSServerResponseError.invalidCommand
		}

		return value
	}

	static func handle(option: GameState.Option, value: Bool, with context: WSClientMessageContext) throws {
		guard let lobbyContext = context as? WSClientLobbyContext else {
			throw WSServerResponseError.optionNonModifiable
		}

		lobbyContext.options.set(option, to: value)
		lobbyContext.userWS.webSocket.send(response: .setOption(option, value))
		lobbyContext.opponentWS?.webSocket.send(response: .setOption(option, value))
	}
}
