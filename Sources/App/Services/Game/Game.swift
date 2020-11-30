//
//  Game.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Vapor
import HiveEngine

class Game {
	let state: State
	var host: WebSocketContext?
	var opponent: WebSocketContext?
	var spectators: [User.IDValue: WebSocketContext] = [:]

	init(state: State) {
		self.state = state
	}

	func userIsPlaying(_ userId: User.IDValue) -> Bool {
		state.host.id == userId || state.opponent?.id == userId
	}

	func userIsSpectating(_ userId: User.IDValue) -> Bool {
		spectators.keys.contains(userId)
	}

	func context(forUser userId: User.IDValue) -> WebSocketContext? {
		if userId == state.host.id {
			return host
		} else if userId == state.opponent?.id {
			return opponent
		}

		return nil
	}

	func opponentContext(forUser userId: User.IDValue) -> WebSocketContext? {
		if userId == state.host.id {
			return opponent
		} else if userId == state.opponent?.id {
			return host
		}

		return nil
	}

	// Managing players and spectators

	func setContext(_ context: WebSocketContext, forUser userId: User.IDValue) {
		if userId == state.host.id {
			host = context
		} else if userId == state.opponent?.id {
			opponent = context
		}
	}

	func addSpectator(_ context: WebSocketContext, asUser userId: User.IDValue) {
		spectators[userId] = context
	}

	func removeSpectator(_ userId: User.IDValue) {
		spectators[userId] = nil
	}
}

// MARK: State

extension Game {
	class State {
		let id: Match.IDValue
		var host: Game.Player
		var opponent: Game.Player?

		var gameOptions: Set<GameState.Option>
		var options: Set<Match.Option>

		var hiveGameState: HiveEngine.GameState?

		var hasStarted: Bool {
			hiveGameState != nil
		}

		var hasEnded: Bool {
			hiveGameState?.hasGameEnded ?? false
		}

		var winner: User.IDValue? {
			switch hiveGameState?.endState {
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

		convenience init(match: Match) throws {
			self.init(
				id: try match.requireID(),
				hostId: match.$host.id,
				opponentId: match.$opponent.id,
				options: match.options,
				gameOptions: match.gameOptions
			)
		}

		// MARK: Players

		func toggleUserReady(_ userId: User.IDValue) {
			if userId == host.id {
				host.isReady.toggle()
			} else if userId == opponent?.id {
				opponent?.isReady.toggle()
			}
		}

		func isUserReady(_ userId: User.IDValue) -> Bool {
			if userId == host.id {
				return host.isReady
			} else if userId == opponent?.id {
				return opponent?.isReady ?? false
			}

			return false
		}

		func isUserTurn(_ userId: User.IDValue) -> Bool {
			if userId == host.id {
				return options.contains(.hostIsWhite)
					? hiveGameState?.currentPlayer == .white
					: hiveGameState?.currentPlayer == .black
			} else if userId == opponent?.id {
				return options.contains(.hostIsWhite)
					? hiveGameState?.currentPlayer == .black
					: hiveGameState?.currentPlayer == .white
			}

			return false
		}

		func opponent(for userId: User.IDValue) -> User.IDValue? {
			if userId == host.id {
				return opponent?.id
			} else if userId == opponent?.id {
				return host.id
			}

			return nil
		}

		// MARK: Options

		func setOption(_ option: GameClientMessage.Option, to value: Bool) {
			switch option {
			case .gameOption(let option):
				gameOptions.set(option, to: value)
			case .matchOption(let option):
				options.set(option, to: value)
			}
		}

		// MARK: Connection

		func userDidDisconnect(_ userId: User.IDValue) {
			if userId == host.id {
				host.isConnected = false
			} else if userId == opponent?.id {
				opponent?.isConnected = false
			}
		}

		func userDidConnect(_ userId: User.IDValue) {
			if userId == host.id {
				host.isConnected = true
			} else if userId == opponent?.id {
				opponent?.isConnected = true
			}
		}

		func isUserConnected(_ userId: User.IDValue) -> Bool {
			if userId == host.id {
				return host.isConnected
			} else if userId == opponent?.id {
				return opponent?.isConnected ?? false
			}

			return false
		}
	}
}

// MARK: - Player

extension Game {
	struct Player {
		let id: User.IDValue
		var isConnected: Bool = true
		var isReady: Bool = false
	}
}

// MARK: - Messages

extension Game {
	func sendResponseToAll(_ response: GameServerResponse) {
		host?.webSocket.send(response: response)
		opponent?.webSocket.send(response: response)
		spectators.values.forEach { $0.webSocket.send(response: response) }
	}

	func sendErrorToAll(_ error: GameServerResponseError, fromUser userId: User.IDValue?) {
		host?.webSocket.send(error: error, fromUser: userId)
		opponent?.webSocket.send(error: error, fromUser: userId)
		spectators.values.forEach { $0.webSocket.send(error: error, fromUser: userId) }
	}
}
