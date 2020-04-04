//
//  WSServerResponseError.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Foundation
import HiveEngine

enum WSServerResponseError: LocalizedError {
	// Client errors
	case invalidMovement(String)
	case notPlayerTurn
	case optionNonModifiable
	case invalidCommand

	// Server/state errors
	case optionValueNotUpdated(GameState.Option, String)
	case unknownError(Error)

	var errorCode: Int {
		switch self {
		case .invalidMovement:       return 101
		case .notPlayerTurn:         return 102
		case .optionNonModifiable:   return 103
		case .invalidCommand:        return 199
		case .optionValueNotUpdated: return 201
		case .unknownError:          return 999
		}
	}

	var errorDescription: String {
		switch self {
		case .invalidMovement(let move):
			return #"Move "\#(move)" not valid"#
		case .notPlayerTurn:
			return "Not player turn"
		case .optionNonModifiable:
			return "Options cannot be modified"
		case .invalidCommand:
			return "Invalid command"
		case .optionValueNotUpdated(let option, let value):
			return #"Could not set "\#(option)" to "\#(value)""#
		case .unknownError(let error):
			return error.localizedDescription
		}
	}
}
