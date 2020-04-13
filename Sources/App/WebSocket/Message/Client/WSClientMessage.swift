//
//  WSClientMessage.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

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

extension WSClientMessageContext {
	var isUserHost: Bool {
		user == match.hostId
	}
}

enum WSClientMessage {
	case playMove(RelativeMovement)
	case sendMessage(String)
	case setOption(GameState.Option, Bool)
	case playerReady
	case forfeit

	init(from: String) throws {
		if from.starts(with: "SET") {
			self = try .setOption(WSClientMessage.extractOption(from: from), WSClientMessage.extractOptionValue(from: from))
		} else if from.starts(with: "MSG") {
			self = try .sendMessage(WSClientMessage.extractMessage(from: from))
		} else if from.starts(with: "GLHF") {
			self = .playerReady
		} else if from.starts(with: "MOV") {
			self = try .playMove(WSClientMessage.extractMovement(from: from))
		} else if from.starts(with: "FF") {
			self = .forfeit
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
		case .forfeit:
			try WSClientMessage.handle(playerForfeit: context.user, with: context)
		}
	}
}
