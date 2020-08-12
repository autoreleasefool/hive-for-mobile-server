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
	var host: Game.Player
	var opponent: Game.Player?

	var gameOptions: Set<GameState.Option>
	var options: Set<Match.Option>

	var state: GameState?

	var hasStarted: Bool {
		state != nil
	}

	var hasEnded: Bool {
		state?.hasGameEnded ?? false
	}

	var winner: User.IDValue? {
		switch state?.endState {
		case .draw, .none: return nil
		case .playerWins(.black): return options.contains(.hostIsWhite) ? opponent?.id : host.id
		case .playerWins(.white): return options.contains(.hostIsWhite) ? host.id : opponent?.id
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
		self.host = .init(id: hostId)
		if let opponentId = opponentId {
			self.opponent = .init(id: opponentId)
		}
		self.options = OptionSet.parse(options)
		self.gameOptions = OptionSet.parse(gameOptions)
	}

	convenience init?(match: Match) {
		guard let id = try? match.requireID() else { return nil }
		self.init(
			id: id,
			hostId: match.$host.id,
			opponentId: match.$opponent.id,
			options: match.options,
			gameOptions: match.gameOptions
		)
	}

	func togglePlayerReady(player: User.IDValue) {
		switch player {
		case host.id: host.isReady.toggle()
		case opponent?.id: opponent?.isReady.toggle()
		default: break
		}
	}

	func isPlayerReady(player: User.IDValue) -> Bool {
		switch player {
		case host.id: return host.isReady
		case opponent?.id: return opponent?.isReady ?? false
		default: return false
		}
	}

	func isPlayerTurn(player: User.IDValue) -> Bool {
		switch player {
		case host.id: return options.contains(.hostIsWhite)
			? state?.currentPlayer == .white
			: state?.currentPlayer == .black
		case opponent?.id: return options.contains(.hostIsWhite)
			? state?.currentPlayer == .black
			: state?.currentPlayer == .white
		default: return false
		}
	}

	func opponent(for userId: User.IDValue) -> User.IDValue? {
		switch userId {
		case host.id: return opponent?.id
		case opponent?.id: return host.id
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

	func playerIsReconnecting(player: User.IDValue) {
		switch player {
		case host.id: host.hasReconnectedSuccessfully = false
		case opponent?.id: opponent?.hasReconnectedSuccessfully = false
		default: break
		}
	}

	func playerDidReconnect(player: User.IDValue) {
		switch player {
		case host.id: host.hasReconnectedSuccessfully = true
		case opponent?.id: opponent?.hasReconnectedSuccessfully = true
		default: break
		}
	}

	func hasPlayerReconnected(player: User.IDValue) -> Bool {
		switch player {
		case host.id: return host.hasReconnectedSuccessfully
		case opponent?.id: return opponent?.hasReconnectedSuccessfully ?? false
		default: return false
		}
	}
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
			game.host.id == userId || game.opponent?.id == userId
		}

		func add(context: WebSocketContext, forUser userId: User.IDValue) {
			switch userId {
			case game.host.id: host = context
			case game.opponent?.id: opponent = context
			default: break
			}
		}

		func context(forUser userId: User.IDValue) -> WebSocketContext? {
			switch userId {
			case game.host.id: return host
			case game.opponent?.id: return opponent
			default: return nil
			}
		}

		func opponentContext(forUser userId: User.IDValue) -> WebSocketContext? {
			switch userId {
			case game.host.id: return opponent
			case game.opponent?.id: return host
			default: return nil
			}
		}
	}
}

// MARK: User state

extension Game {
	struct Player {
		let id: User.IDValue
		var isReady: Bool = false
		var hasReconnectedSuccessfully = false
	}
}

// MARK: - WebSocketContext

struct WebSocketContext {
	let webSocket: WebSocket
	let request: Request
}
