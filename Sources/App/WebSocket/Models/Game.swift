//
//  Game.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Vapor
import HiveEngine

class Game {
	let id: Match.ID
	var hostId: User.ID
	var opponentId: User.ID?

	var hostReady: Bool = false
	var opponentReady: Bool = false
	var gameOptions: Set<GameState.Option>
	var options: Set<Match.Option>

	var state: GameState?

	var hasStarted: Bool {
		state != nil
	}

	var hasEnded: Bool {
		state?.isEndGame ?? false
	}

	var winner: User.ID? {
		guard let winner = state?.winner else { return nil }
		if winner.count == 2 {
			return nil
		}

		switch winner.first {
		case .white: return options.contains(.hostIsWhite) ? hostId : opponentId
		case .black: return options.contains(.hostIsWhite) ? opponentId : hostId
		case .none: return nil
		}
	}

	init(id: Match.ID, hostId: User.ID, opponentId: User.ID? = nil, options: String, gameOptions: String) {
		self.id = id
		self.hostId = hostId
		self.opponentId = opponentId
		self.options = OptionSet.parse(options)
		self.gameOptions = OptionSet.parse(gameOptions)
	}

	convenience init?(match: Match) {
		guard let id = try? match.requireID() else { return nil }
		self.init(
			id: id,
			hostId: match.hostId,
			opponentId: match.opponentId,
			options: match.options,
			gameOptions: match.gameOptions
		)
	}

	func togglePlayerReady(player: User.ID) {
		switch player {
		case hostId: hostReady.toggle()
		case opponentId: opponentReady.toggle()
		default: break
		}
	}

	func isPlayerReady(player: User.ID) -> Bool {
		switch player {
		case hostId: return hostReady
		case opponentId: return opponentReady
		default: return false
		}
	}

	func isPlayerTurn(player: User.ID) -> Bool {
		switch player {
		case hostId: return options.contains(.hostIsWhite)
			? state?.currentPlayer == .white
			: state?.currentPlayer == .black
		case opponentId: return options.contains(.hostIsWhite)
			? state?.currentPlayer == .black
			: state?.currentPlayer == .white
		default: return false
		}
	}

	func opponent(for userId: User.ID) -> User.ID? {
		switch userId {
		case hostId: return opponentId
		case opponentId: return hostId
		default: return nil
		}
	}

	func setOption(_ option: GameClientMessage.Option, to value: Bool) {
		switch option {
		case .gameOption(let option):
			gameOptions.set(option, to: value)
		case .matchOption(let option):
			options.set(option, to: value)
		}
	}
}

struct WebSocketContext {
	let webSocket: WebSocket
	let request: Request
}

class GameSession {
	let game: Game
	var host: WebSocketContext?
	var opponent: WebSocketContext?

	init(game: Game) {
		self.game = game
	}

	func contains(_ userId: User.ID) -> Bool {
		game.hostId == userId || game.opponentId == userId
	}

	func add(context: WebSocketContext, forUser userId: User.ID) {
		if userId == game.hostId {
			host = context
		} else if userId == game.opponentId {
			opponent = context
		}
	}

	func context(forUser userId: User.ID) -> WebSocketContext? {
		if userId == game.hostId {
			return host
		} else if userId == game.opponentId {
			return opponent
		}
		return nil
	}

	func opponentContext(forUser userId: User.ID) -> WebSocketContext? {
		if userId == game.hostId {
			return opponent
		} else if userId == game.hostId {
			return host
		}
		return nil
	}
}
