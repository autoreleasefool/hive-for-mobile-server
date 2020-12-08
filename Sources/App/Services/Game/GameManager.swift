//
//  GameManager.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Fluent
import HiveEngine
import Vapor

final class GameManager: GameService {
	private var games: [Match.IDValue: Game] = [:]

	init() {}

	func doesActiveGameExist(withId gameId: Match.IDValue) -> Bool {
		guard let game = games[gameId] else { return false }
		return game.state.host.isConnected || game.state.opponent?.isConnected == true
	}

	// MARK: Adding players

	func addGame(_ game: Game, on req: Request) throws -> EventLoopFuture<Void> {
		req.logger.debug("Adding game (\(String(describing: game.state.id)))")
		self.games[game.state.id] = game
		return req.eventLoop.makeSucceededFuture(())
	}

	func addUser(_ user: User, to match: Match, on req: Request) throws -> EventLoopFuture<Void> {
		let userId = try user.requireID()
		let matchId = try match.requireID()
		req.logger.debug("Adding user (\(userId)) to (\(matchId))")

		guard let game = games[matchId] else {
			req.logger.debug("Match (\(matchId)) is not open to join")
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard game.state.host.id != userId else {
			return req.eventLoop.makeSucceededFuture(())
		}

		guard game.state.opponent?.id == nil || game.state.opponent?.id == userId else {
			req.logger.debug("Match (\(matchId)) is full")
			throw Abort(.badRequest, reason: #"Match \#(matchId) is full"#)
		}

		return match.add(opponent: userId, on: req)
			.map { _ in
				req.logger.debug("Added user (\(userId)) to match (\(matchId))")
				self.games[matchId]?.state.opponent = Game.Player(id: userId)
				self.games[matchId]?.host?.webSocket.send(response: .playerJoined(userId))
				return ()
			}
	}

	// MARK: Connecting players

	func connectPlayer(_ user: User, ws: WebSocket, on req: Request) throws {
		let userId = try user.requireID()
		let wsContext = WebSocketContext(webSocket: ws, request: req)

		guard let rawMatchId = req.parameters.get(MatchController.Parameter.match.rawValue),
			let matchId = Match.IDValue(uuidString: rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined from path")
		}

		req.logger.debug("Connecting to websocket: user (\(userId)) to (\(matchId))")

		guard games[matchId]?.userIsPlaying(userId) == true else {
			req.logger.debug("Cannot connect user (\(userId)) to (\(matchId))")
			throw Abort(.forbidden, reason: "Cannot connect to a game you are not a part of")
		}

		games[matchId]?.setContext(wsContext, forUser: userId)

		ws.pingInterval = .seconds(30)
		ws.onText { [unowned self] ws, text in
			let reqId = UUID()
			req.logger.debug("[\(reqId)]: \(text)")
			guard let game = self.games[matchId] else {
				req.logger.debug(#"Match with ID "\#(matchId)" is not open to play."#)
				return
			}

			guard let context = game.context(forUser: userId) else {
				req.logger.debug("[\(reqId)]: Invalid command")
				ws.send(error: .invalidCommand, fromUser: userId)
				return
			}

			do {
				let message = try GameClientMessage(from: text)
				let resolver = try GameActionResolver(game: game, userId: userId, message: message)
				resolver.resolve { [unowned self] result in
					switch result {
					case .success(let result):
						do {
							try self.handle(result: result, context: context, game: game)
						} catch {
							handle(error: error, userId: userId, game: game)
						}
					case .failure(let error):
						self.handleServerError(error: error, userId: userId, game: game)
					}
				}
			} catch {
				self.handle(error: error, userId: userId, game: game)
			}
		}
		_ = ws.onClose.always { [unowned self] _ in
			guard let game = self.games[matchId] else { return }
			game.state.userDidDisconnect(userId)

			if game.state.host.id == userId {
				req.eventLoop.scheduleTask(in: .minutes(5)) {
					ExpiredGameJob(id: matchId)
						.invoke(req.application)
				}
			}
		}
	}

	func connectSpectator(_ user: User, ws: WebSocket, on req: Request) throws {
		let userId = try user.requireID()
		let displayName = user.displayName
		let wsContext = WebSocketContext(webSocket: ws, request: req)

		guard let rawMatchId = req.parameters.get(MatchController.Parameter.match.rawValue),
			let matchId = Match.IDValue(uuidString: rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined from path")
		}

		req.logger.debug("Connecting spectator to websocket: user (\(userId)) to match (\(matchId))")

		guard let game = games[matchId] else {
			req.logger.debug("Match (\(matchId)) not open to spectate")
			throw Abort(.badRequest, reason: "Match \(matchId) is not open to spectate")
		}

		guard !game.userIsPlaying(userId) else {
			req.logger.debug("User (\(userId)) cannot spectate a match they are participating in")
			throw Abort(.badRequest, reason: "Cannot spectate a match you are participating in")
		}

		guard game.state.opponent != nil,
			game.state.hasStarted,
			let state = game.state.hiveGameState else {
			req.logger.debug("Match (\(matchId)) has not started")
			throw Abort(.badRequest, reason: "Cannot spectate a match that has not started")
		}

		guard !game.userIsSpectating(userId) else {
			req.logger.debug("User (\(userId)) already spectating match (\(matchId))")
			throw Abort(.badRequest, reason: "Cannot spectate a match you are already spectating")
		}

		game.sendResponseToAll(.spectatorJoined(name: displayName))
		game.addSpectator(wsContext, asUser: userId)

		_ = ws.onClose.always { [unowned self] _ in
			guard let game = self.games[matchId] else { return }
			game.removeSpectator(userId)
			game.sendResponseToAll(.spectatorLeft(name: displayName))
		}

		ws.pingInterval = .seconds(30)
		ws.onText { [unowned self] ws, text in
			let reqId = UUID()
			req.logger.debug("[\(reqId)]: \(text)")
			guard let game = self.games[matchId] else {
				req.logger.debug(#"Match with ID "\#(matchId)" is not open."#)
				return
			}

			if let message = try? GameClientMessage(from: text), case let .sendMessage(string) = message {
				game.sendResponseToAll(.message(userId, string))
			} else {
				ws.send(error: .invalidCommand, fromUser: userId)
			}
		}
		ws.send(response: .state(state))
	}

	// MARK: Removing players

	@discardableResult
	private func remove(
		opponent: User.IDValue,
		from matchId: Match.IDValue,
		on req: Request
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		req.logger.debug("Removing (\(opponent)) from (\(matchId))")
		guard let game = games[matchId] else {
			req.logger.debug("Match (\(matchId)) is not open")
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open"#)
		}

		guard game.state.opponent?.id == opponent else {
			req.logger.debug("User (\(opponent)) is not part of (\(matchId))")
			throw Abort(.badRequest, reason: #"Cannot leave match \#(matchId) you are not a part of"#)
		}

		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.remove(opponent: opponent, on: req) }
			.map { [weak self] _ in
				req.logger.debug("Removed user (\(opponent)) from (\(matchId))")
				self?.games[matchId]?.state.opponent = nil
				self?.games[matchId]?.host?.webSocket.send(response: .playerLeft(opponent))
				return .ok
			}
	}

	// MARK: Game Flow

	private func startMatch(context: WebSocketContext, game: Game) throws {
		context.request.logger.debug("Starting match (\(game.state.id))")
		guard !game.state.hasStarted else {
			context.request.logger.debug("Already started match (\(game.state.id))")
			throw Abort(.internalServerError, reason: #"Cannot start match "\#(game.state.id)" that already started"#)
		}

		Match.find(game.state.id, on: context.request.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(game.state.id)"))
			.flatMapThrowing { try $0.begin(on: context.request) }
			.whenComplete { result in
				switch result {
				case .success:
					context.request.logger.debug("Started match (\(game.state.id)). Sending state to users")
					let state = GameState(options: game.state.gameOptions)
					game.state.hiveGameState = state
					game.sendResponseToAll(.state(state))
				case .failure:
					context.request.logger.debug("Failed to start match (\(game.state.id))")
					self.handleServerError(error: .failedToStartMatch, userId: game.state.host.id, game: game)
					if let opponent = game.state.opponent?.id {
						self.handleServerError(error: .failedToStartMatch, userId: opponent, game: game)
					}
				}
			}
	}

	private func endMatch(context: WebSocketContext, game: Game) throws {
		context.request.logger.debug("Ending match (\(game.state.id))")
		guard game.state.hasEnded else {
			context.request.logger.debug("Cannot end match (\(game.state.id)) that has not ended")
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(game.state.id)" before game has ended"#)
		}

		games[game.state.id] = nil

		Match.find(game.state.id, on: context.request.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(game.state.id)"))
			.flatMapThrowing { try $0.end(winner: game.state.winner, on: context.request) }
			.whenComplete { result in
				switch result {
				case .success:
					context.request.logger.debug("Successfully ended match (\(game.state.id))")
				case .failure:
					context.request.logger.debug("Failed to end match (\(game.state.id))")
					self.handleServerError(error: .failedToEndMatch, userId: game.state.host.id, game: game)
					if let opponent = game.state.opponent?.id {
						self.handleServerError(error: .failedToEndMatch, userId: opponent, game: game)
					}
				}
			}
	}

	private func forfeitMatch(winner: User.IDValue, context: WebSocketContext, game: Game) throws {
		context.request.logger.debug("Forfeiting match (\(game.state.id))")
		guard game.state.hasStarted else {
			context.request.logger.debug("Cannot forfeit match (\(game.state.id))")
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(game.state.id)" before game has ended"#)
		}

		games[game.state.id] = nil

		Match.find(game.state.id, on: context.request.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(game.state.id)"))
			.flatMapThrowing { try $0.end(winner: winner, on: context.request) }
			.whenComplete { result in
				switch result {
				case .success:
					context.request.logger.debug("Successfully forfeit match (\(game.state.id))")
				case .failure:
					context.request.logger.debug("Failed to forfeit match (\(game.state.id))")
					self.handleServerError(error: .failedToEndMatch, userId: game.state.host.id, game: game)
					if let opponent = game.state.opponent?.id {
						self.handleServerError(error: .failedToEndMatch, userId: opponent, game: game)
					}
				}
			}
	}

	@discardableResult
	private func delete(match matchId: Match.IDValue, on req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		req.logger.debug("Deleting match (\(matchId))")
		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.delete(on: req.db) }
			.transform(to: .ok)
	}

	@discardableResult
	private func updateOptions(
		matchId: Match.IDValue,
		options: Set<Match.Option>,
		gameOptions: Set<GameState.Option>,
		on req: Request
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		req.logger.debug("Updating options in match (\(matchId))")
		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.updateOptions(options: options, gameOptions: gameOptions, on: req) }
			.transform(to: .ok)
	}

	// MARK: Resolvers

	private func handle(
		result: GameActionResolver.Result?,
		context: WebSocketContext,
		game: Game
	) throws {
		switch result {
		case .shouldStartMatch:
			try startMatch(context: context, game: game)
		case .shouldEndMatch:
			try endMatch(context: context, game: game)
		case .shouldUpdateOptions:
			try updateOptions(matchId: game.state.id, options: game.state.options, gameOptions: game.state.gameOptions, on: context.request)
		case .shouldForfeitMatch(let winner):
			try forfeitMatch(winner: winner, context: context, game: game)
		case .shouldRemoveOpponent(let user):
			try remove(opponent: user, from: game.state.id, on: context.request)
		case .shouldDeleteMatch:
			games[game.state.id] = nil
			try delete(match: game.state.id, on: context.request)
		case .none:
			break
		}
	}

	// MARK: Errors

	private func handleServerError(error: GameServerResponseError, userId: User.IDValue, game: Game) {
		if error.shouldSendToOpponent {
			game.sendErrorToAll(error, fromUser: userId)
		} else {
			game.context(forUser: userId)?.webSocket.send(error: error, fromUser: userId)
		}
	}

	private func handle(error: Error, userId: User.IDValue, game: Game) {
		if let serverError = error as? GameServerResponseError {
			self.handleServerError(error: serverError, userId: userId, game: game)
		} else {
			self.handleServerError(error: .unknownError(nil), userId: userId, game: game)
		}
	}
}
