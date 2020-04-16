//
//  GameServerResponseError.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Foundation
import HiveEngine

enum GameServerResponseError: LocalizedError {
	// Client errors
	case invalidMovement(String)
	case notPlayerTurn
	case optionNonModifiable
	case invalidCommand

	// Server/state errors
	case optionValueNotUpdated(GameState.Option, String)
	case failedToEndMatch

	// Other errors
	case unknownError(Error?)

	var errorCode: Int {
		switch self {
		case .invalidMovement:       return 101
		case .notPlayerTurn:         return 102
		case .optionNonModifiable:   return 103
		case .invalidCommand:        return 199
		case .optionValueNotUpdated: return 201
		case .failedToEndMatch:      return 202
		case .unknownError:          return 999
		}
	}

	var errorDescription: String {
		switch self {
		case .invalidMovement(let move):
			return #"Move "\#(move)" not valid."#
		case .notPlayerTurn:
			return "It's not your turn."
		case .optionNonModifiable:
			return "You cannot modify game options at this time."
		case .invalidCommand:
			return "Invalid command."
		case .optionValueNotUpdated(let option, let value):
			return #"Failed to set "\#(option)" to "\#(value)"."#
		case .failedToEndMatch:
			return "The match is over, but an error occurred."
		case .unknownError(let error):
			return error?.localizedDescription ?? "Unknown error."
		}
	}

	var shouldSendToOpponent: Bool {
		switch self {
		case .invalidMovement,
			.notPlayerTurn,
			.invalidCommand,
			.optionValueNotUpdated,
			.optionNonModifiable,
			.unknownError:
			return false
		case .failedToEndMatch:
			return true
		}
	}
}
