//
//  WSServerResponse.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import HiveEngine

enum WSServerResponse {
	case state(GameState)
	case setOption(GameState.Option, Bool)
	case setPlayerReady(User.ID, Bool)
	case message(User.ID, String)
	case forfeit(User.ID)
//	case startGame
//	case forfeit
//	case error(WSServerError)
}

extension WebSocket {
	func send(response: WSServerResponse) {
		switch response {
		case .state(let state):
			self.send("STATE \(state.gameString)")
		case .setOption(let option, let value):
			self.send("SET \(option) \(value)")
		case .setPlayerReady(let userId, let isReady):
			self.send("READY \(userId) \(isReady)")
		case .message(let userId, let message):
			self.send("MSG \(userId) \(message)")
//		case .startGame:
//			self.send("GLHF")
		case .forfeit(let user):
			self.send("FF \(user)")
//		case .error(let error):
//			self.send("ERR \(error.errorDescription)")
		}
	}

	func send(error: WSServerResponseError, fromUser: User.ID?) {
		self.send("ERR \(fromUser?.description ?? "null") \(error.errorCode) \(error.errorDescription)")
	}
}
