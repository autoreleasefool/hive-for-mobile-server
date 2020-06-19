//
//  Game.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Vapor
import HiveEngine

class Game {
	let id: Match.IDValue
	var hostId: User.IDValue
	var opponentId: User.IDValue?

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

	var winner: User.IDValue? {
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

	init(
		id: Match.IDValue,
		hostId: User.IDValue,
		opponentId: User.IDValue? = nil,
		options: String,
		gameOptions: String
	) {
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

	func togglePlayerReady(player: User.IDValue) {
		switch player {
		case hostId: hostReady.toggle()
		case opponentId: opponentReady.toggle()
		default: break
		}
	}

	func isPlayerReady(player: User.IDValue) -> Bool {
		switch player {
		case hostId: return hostReady
		case opponentId: return opponentReady
		default: return false
		}
	}

	func isPlayerTurn(player: User.IDValue) -> Bool {
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

	func opponent(for userId: User.IDValue) -> User.IDValue? {
		switch userId {
		case hostId: return opponentId
		case opponentId: return hostId
		default: return nil
		}
	}

//	func setOption(_ option: GameClientMessage.Option, to value: Bool) {
//		switch option {
//		case .gameOption(let option):
//			gameOptions.set(option, to: value)
//		case .matchOption(let option):
//			options.set(option, to: value)
//		}
//	}
 }

// MARK: - GameSession

extension Game {
	class Session {
		let game: Game
		var host: WebSocketContext?
		var opponent: WebSocketContext?

		init(game: Game) {
			self.game = game
		}

		func contains(_ userId: User.IDValue) -> Bool {
			[game.hostId, game.opponentId].contains(userId)
		}

		func add(context: WebSocketContext, forUser userId: User.IDValue) {
			if userId == game.hostId {
				host = context
			} else if userId == game.opponentId {
				opponent = context
			}
		}

		func context(forUser userId: User.IDValue) -> WebSocketContext? {
			if userId == game.hostId {
				return host
			} else if userId == game.opponentId {
				return opponent
			}

			return nil
		}

		func opponentContext(forUser userId: User.IDValue) -> WebSocketContext? {
			if userId == game.hostId {
				return opponent
			} else if userId == game.opponentId {
				return host
			}

			return nil
		}
	}
}

// MARK: - WebSocketContext

struct WebSocketContext {
	let webSocket: WebSocket
	let request: Request
}
