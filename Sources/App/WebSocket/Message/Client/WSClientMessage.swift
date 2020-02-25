import Vapor
import HiveEngine

protocol WSClientMessageContext: class {
	var user: User.ID { get }
	var opponent: User.ID? { get }
	var matchId: Match.ID { get }
	var match: Match { get }

	var userWS: WebSocketContext { get }
	var opponentWS: WebSocketContext? { get }
}

enum WSClientMessage {
	case playMove(RelativeMovement)
	case sendMessage(String)
	case setOption(GameState.Option, Bool)
	case playerReady

	init(from: String) throws {
		if from.starts(with: "SET") {
			self = try .setOption(WSClientMessage.extractOption(from: from), WSClientMessage.extractOptionValue(from: from))
		} else if from.starts(with: "MSG") {
			self = try .sendMessage(WSClientMessage.extractMessage(from: from))
		} else if from.starts(with: "GLHF") {
			self = .playerReady
		} else if from.starts(with: "MOV") {
			self = try .playMove(WSClientMessage.extractMovement(from: from))
		}

		throw WSServerResponseError.invalidCommand
	}

	func handle(_ context: WSClientMessageContext) throws {
		switch self {
		case .playMove(let movement):
			try WSClientMessage.handle(movement: movement, with: context)
		case .sendMessage(let message):
			try WSClientMessage.handle(message: message, with: context)
		case .setOption(let option, let value):
			try WSClientMessage.handle(option: option, value: value, with: context)
		case .playerReady:
			try WSClientMessage.handle(playerReady: context.user, with: context)
		}
	}
}
