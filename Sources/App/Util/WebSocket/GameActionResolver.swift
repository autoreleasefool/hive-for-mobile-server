//
//  GameActionResolver.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-10-18.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import HiveEngine
import Vapor

struct GameActionResolver {
	private let id = UUID()
	private let session: Game.Session
	private let userId: User.IDValue
	private let message: GameClientMessage
	private let context: WebSocketContext

	init(session: Game.Session, userId: User.IDValue, message: GameClientMessage) throws {
		self.session = session
		self.userId = userId
		self.message = message

		guard let context = session.context(forUser: userId) else {
			throw Error.invalidSession
		}

		self.context = context
	}

	func resolve(completion: @escaping (Swift.Result<Result?, GameServerResponseError>) -> Void) {
		switch message {
		case .playerReady:
			togglePlayerReady(completion: completion)
		case .playMove(let movement):
			play(movement: movement, completion: completion)
		case .sendMessage(let string):
			send(message: string, completion: completion)
		case .setOption(let option, let value):
			set(option: option, to: value, completion: completion)
		case .forfeit:
			forfeit(completion: completion)
		}
	}

	private func togglePlayerReady(completion: (Swift.Result<Result?, GameServerResponseError>) -> Void) {
		debugLog("Toggling user {{user}} ready state")
		guard !session.game.hasStarted,
					session.game.opponent?.id != nil else {
			return completion(.failure(.invalidCommand))
		}

		debugLog("Toggling ready state")
		session.game.togglePlayerReady(player: userId)

		let readyResponse = GameServerResponse.setPlayerReady(userId, session.game.isPlayerReady(player: userId))
		session.sendResponseToAll(readyResponse)

		guard session.game.host.isReady && session.game.opponent?.isReady == true else {
			return completion(.success(nil))
		}

		debugLog("Both players ready. Starting match {{match}}")
		completion(.success(.shouldStartMatch))
	}

	private func play(movement: RelativeMovement, completion: @escaping (Swift.Result<Result?, GameServerResponseError>) -> Void) {
		debugLog("User {{user}} is playing move {{move}}", args: ["move": movement.description])
		guard session.game.hasStarted,
					let state = session.game.state else {
			debugLog("Match {{match}} is not in a valid state to play")
			return completion(.failure(.invalidCommand))
		}

		guard session.game.isPlayerTurn(player: userId) else {
			debugLog("User {{user}} is not the current player")
			return completion(.failure(.notPlayerTurn))
		}

		guard state.apply(relativeMovement: movement) else {
			debugLog("Move {{move}} is not valid", args: ["move": movement.description])
			return completion(.failure(.invalidMovement(movement.notation)))
		}

		debugLog("Confirming move {{move}}", args: ["move": movement.description])
		let matchMovement = MatchMovement(from: movement, userId: userId, matchId: session.game.id, ordinal: state.move)
		matchMovement.save(on: context.request.db)
			.whenComplete { result in
				switch result {
				case .success:
					session.sendResponseToAll(.state(state))
					if state.hasGameEnded {
						session.sendResponseToAll(.gameOver(session.game.winner))
					}
					completion(.success(nil))
				case .failure(let error):
					completion(.failure(.unknownError(error)))
				}
			}

		guard state.hasGameEnded else { return }

		debugLog("Ending match {{match}}")
		completion(.success(.shouldEndMatch))
	}

	private func send(message: String, completion: (Swift.Result<Result?, GameServerResponseError>) -> Void) {
		debugLog("Sending message \"{{message}}\" to all users", args: ["message": message])
		session.sendResponseToAll(.message(userId, message))
		completion(.success(nil))
	}

	private func set(option: GameClientMessage.Option, to value: Bool, completion: (Swift.Result<Result?, GameServerResponseError>) -> Void) {
		debugLog(
			"User {{user}} is setting option {{option}} to {{value}}",
			args: [
				"option": "\(option)",
				"value": value.description
			]
		)
		guard !session.game.hasStarted else {
			debugLog("Cannot set option for match {{match}} that has started")
			return completion(.failure(.invalidCommand))
		}

		guard userId == session.game.host.id else {
			debugLog("User {{user}} is not the host")
			return completion(.failure(.optionNonModifiable))
		}

		debugLog(
			"Setting option {{option}} to {{value}}",
			args: [
				"option": "\(option)",
				"value": value.description
			]
		)
		session.game.setOption(option, to: value)
		session.sendResponseToAll(.setOption(option.asServerOption, value))
		completion(.success(.shouldUpdateOptions))
	}

	private func forfeit(completion: (Swift.Result<Result?, GameServerResponseError>) -> Void) {
		if session.game.hasStarted {
			debugLog("User {{user}} is forfeiting match {{match}}")
			guard let winner = session.game.opponent(for: userId) else {
				return completion(.failure(.invalidCommand))
			}

			session.sendResponseToAll(.forfeit(userId))
			completion(.success(.shouldForfeitMatch(winner: winner)))
		} else {
			if session.game.host.id == userId {
				debugLog("Host {{user}} is leaving match {{match}}")
				session.opponentContext(forUser: userId)?.webSocket.send(response: .playerLeft(userId))
				debugLog("Deleting match {{match}}")
				completion(.success(.shouldDeleteMatch))
			} else {
				debugLog("{{user}} is leaving match {{match}} before it begins")
				completion(.success(.shouldRemoveOpponent(userId)))
			}
		}
	}
}

// MARK: - Result

extension GameActionResolver {
	enum Result {
		case shouldStartMatch
		case shouldEndMatch
		case shouldUpdateOptions
		case shouldDeleteMatch
		case shouldForfeitMatch(winner: User.IDValue)
		case shouldRemoveOpponent(User.IDValue)
	}

	enum Error: Swift.Error {
		case invalidSession
	}
}

// MARK: Logger

extension GameActionResolver {
	private func debugLog(_ message: String, args: [String: String] = [:]) {
		context.request.logger.debug("[\(id.description)]: \(replacingArguments(in: message, args: args))")
	}

	private func errorLog(_ message: String, args: [String: String] = [:]) {
		context.request.logger.error("[\(id.description)]: \(replacingArguments(in: message, args: args))")
	}

	private func replacingArguments(in message: String, args: [String: String]) -> String {
		let partialMessage = message
			.replacingAll(matching: #"\{\{match\}\}"#, with: args["match"] ?? session.game.id.description)
			.replacingAll(matching: #"\{\{user\}\}"#, with: args["user"] ?? userId.description)

		return args.keys.reduce(partialMessage) { partialMessage, key in
			partialMessage.replacingOccurrences(of: #"\{\{\#(key)}\}"#, with: args[key] ?? "")
		}
	}
}
