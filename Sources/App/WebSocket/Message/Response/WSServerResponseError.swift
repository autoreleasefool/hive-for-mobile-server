import Foundation
import HiveEngine

enum WSServerResponseError: LocalizedError {
	// Client errors
	case invalidMovement(String)
	case notPlayerTurn
	case optionNonModifiable

	// Server/state errors
	case optionValueNotUpdated(GameState.Option, String)

	var errorCode: Int {
		switch self {
		case .invalidMovement:       return 101
		case .notPlayerTurn:         return 102
		case .optionNonModifiable:  return 103
		case .optionValueNotUpdated: return 201
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
		case .optionValueNotUpdated(let option, let value):
			return #"Could not set "\#(option)" to "\#(value)""#
		}
	}
}
