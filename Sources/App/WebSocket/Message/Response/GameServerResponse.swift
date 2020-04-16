//
//  GameServerResponse.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import HiveEngine

enum GameServerResponse {
	case state(GameState)
	case setOption(GameState.Option, Bool)
	case setPlayerReady(User.ID, Bool)
	case message(User.ID, String)
	case forfeit(User.ID)
	case playerJoined(User.ID)
	case playerLeft(User.ID)
}

extension WebSocket {
	func send(response: GameServerResponse) {
		switch response {
		case .state(let state):
			self.send("STATE \(state.gameString)")
		case .setOption(let option, let value):
			self.send("SET \(option) \(value)")
		case .setPlayerReady(let userId, let isReady):
			self.send("READY \(userId) \(isReady)")
		case .message(let userId, let message):
			self.send("MSG \(userId) \(message)")
		case .forfeit(let user):
			self.send("FF \(user)")
		case .playerJoined(let user):
			self.send("JOIN \(user)")
		case .playerLeft(let user):
			self.send("LEAVE \(user)")
		}
	}

	func send(error: GameServerResponseError, fromUser: User.ID?) {
		self.send("ERR \(fromUser?.description ?? "null") \(error.errorCode) \(error.errorDescription)")
	}
}
