//
//  GameClientMessage.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import HiveEngine

enum GameClientMessage {
	enum Option {
		case gameOption(GameState.Option)
		case matchOption(Match.Option)

		var asServerOption: GameServerResponse.Option {
			switch self {
			case .gameOption(let option): return .gameOption(option)
			case .matchOption(let option): return .matchOption(option)
			}
		}
	}

	case playMove(RelativeMovement)
	case sendMessage(String)
	case setOption(Option, Bool)
	case playerReady
	case forfeit

	init(from: String) throws {
		if from.starts(with: "SET") {
			if let gameOption = GameClientMessage.extractGameOption(from: from),
				let value = GameClientMessage.extractOptionValue(from: from) {
				self = .setOption(.gameOption(gameOption), value)
			} else if let option = GameClientMessage.extractOption(from: from),
				let value = GameClientMessage.extractOptionValue(from: from) {
				self = .setOption(.matchOption(option), value)
			} else {
				throw GameServerResponseError.invalidCommand
			}
		} else if from.starts(with: "MSG") {
			self = try .sendMessage(GameClientMessage.extractMessage(from: from))
		} else if from.starts(with: "GLHF") {
			self = .playerReady
		} else if from.starts(with: "MOV") {
			self = try .playMove(GameClientMessage.extractMovement(from: from))
		} else if from.starts(with: "FF") {
			self = .forfeit
		} else {
			throw GameServerResponseError.invalidCommand
		}
	}
}

// MARK: - Message

extension GameClientMessage {
	static func extractMessage(from string: String) throws -> String {
		guard let messageStart = string.firstIndex(of: " ") else {
			throw GameServerResponseError.invalidCommand
		}

		return String(string[messageStart...]).trimmingCharacters(in: .whitespaces)
	}
}

// MARK: - Option

extension GameClientMessage {
	static func extractOption(from string: String) -> Match.Option? {
		guard let optionStart = string.firstIndex(of: " "),
			let optionEnd = string.lastIndex(of: " "),
			let option = Match.Option(
				rawValue: String(string[optionStart..<optionEnd]).trimmingCharacters(in: .whitespaces)
			) else {
			return nil
		}

		return option
	}

	static func extractGameOption(from string: String) -> GameState.Option? {
		guard let optionStart = string.firstIndex(of: " "),
			let optionEnd = string.lastIndex(of: " "),
			let option = GameState.Option(
				rawValue: String(string[optionStart..<optionEnd]).trimmingCharacters(in: .whitespaces)
			) else {
			return nil
		}

		return option
	}

	static func extractOptionValue(from string: String) -> Bool? {
		guard let valueStart = string.lastIndex(of: " "),
			let value = Bool(String(string[valueStart...]).trimmingCharacters(in: .whitespaces)) else {
			return nil
		}

		return value
	}
}

// MARK: - Movement

extension GameClientMessage {
	static func extractMovement(from string: String) throws -> RelativeMovement {
		guard let moveStart = string.firstIndex(of: " "),
			let movement = RelativeMovement(notation: String(string[moveStart...]).trimmingCharacters(in: .whitespaces)) else {
			throw GameServerResponseError.invalidCommand
		}

		return movement
	}
}
