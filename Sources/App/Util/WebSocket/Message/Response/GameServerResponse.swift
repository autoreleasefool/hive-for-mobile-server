//
//  GameServerResponse.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import HiveEngine

enum GameServerResponse {
	enum Option {
		case gameOption(GameState.Option)
		case matchOption(Match.Option)

		var optionName: String {
			switch self {
			case .gameOption(let option): return option.rawValue
			case .matchOption(let option): return option.rawValue
			}
		}
	}

	case state(GameState)
	case gameOver(User.IDValue?)
	case setOption(Option, Bool)
	case setPlayerReady(User.IDValue, Bool)
	case message(User.IDValue, String)
	case forfeit(User.IDValue)
	case playerJoined(User.IDValue)
	case playerLeft(User.IDValue)
	case spectatorJoined(name: String)
	case spectatorLeft(name: String)
}

extension WebSocket {
	func send(response: GameServerResponse) {
		switch response {
		case .state(let state):
			self.send("STATE \(state.gameString)")
		case .gameOver(let userId):
			let winner = userId?.description ?? "null"
			self.send("WINNER \(winner)")
		case .setOption(let option, let value):
			self.send("SET \(option.optionName) \(value)")
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
		case .spectatorJoined(let name):
			self.send("SPECJOIN \(name)")
		case .spectatorLeft(let name):
			self.send("SPECLEAVE \(name)")
		}
	}

	func send(error: GameServerResponseError, fromUser: User.IDValue?) {
		self.send("ERR \(fromUser?.description ?? "null") \(error.errorCode) \(error.errorDescription)")
	}
}
