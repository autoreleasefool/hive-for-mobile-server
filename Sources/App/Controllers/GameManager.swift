//
//  GameManager.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Fluent
import HiveEngine
import Vapor

final class GameManager {
	private var sessions: [Match.IDValue: Game.Session] = [:]

	init() {}

	// MARK: Managing Players

	func add(_ match: Match, on req: Request) throws -> EventLoopFuture<Match> {
		req.logger.debug("Adding match (\(String(describing: match.id)))")
		guard let matchId = try? match.requireID(), let game = Game(match: match) else {
			throw Abort(.internalServerError, reason: "Cannot add match without ID to GameManager.")
		}

		self.sessions[matchId] = Game.Session(game: game)
		return req.eventLoop.makeSucceededFuture(match)
	}

	func add(
		user userId: User.IDValue,
		to matchId: Match.IDValue,
		on req: Request
	) throws -> EventLoopFuture<Match.Join.Response> {
		req.logger.debug("Adding user (\(userId)) to (\(matchId))")
		guard let session = sessions[matchId] else {
			req.logger.debug("Match (\(matchId)) is not open to join")
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard session.game.host.id != userId else {
			return try reconnect(host: userId, to: matchId, session: session, on: req)
		}

		guard session.game.opponent?.id == nil || session.game.opponent?.id == userId else {
			req.logger.debug("Match (\(matchId)) is full")
			throw Abort(.badRequest, reason: #"Match \#(matchId) is full"#)
		}

		return User.find(userId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "User \(userId) could not be found"))
			.flatMap { opponent in
				Match.query(on: req.db)
					.with(\.$host)
					.filter(\.$id == matchId)
					.first()
					.unwrap(or: Abort(.notFound, reason: "Match \(matchId) could not be found"))
					.flatMap { $0.add(opponent: userId, on: req) }
					.flatMapThrowing {
						req.logger.debug("Added user (\(userId)) to match (\(matchId))")
						self.sessions[matchId]?.game.opponent = .init(id: userId)
						self.sessions[matchId]?.host?.webSocket.send(response: .playerJoined(userId))

						return try Match.Join.Response(from: $0, withHost: $0.host, withOpponent: opponent)
					}
			}
	}

	private func reconnect(
		host: User.IDValue,
		to matchId: Match.IDValue,
		session: Game.Session,
		on req: Request
	) throws -> EventLoopFuture<Match.Join.Response> {
		req.logger.debug("Reconnecting user (\(host)) to match (\(matchId))")
		return Match.query(on: req.db)
			.with(\.$host)
			.with(\.$opponent)
			.filter(\.$id == matchId)
			.first()
			.unwrap(or: Abort(.notFound))
			.flatMapThrowing {
				try Match.Join.Response(from: $0, withHost: $0.host, withOpponent: $0.opponent)
			}
	}

	@discardableResult
	func remove(
		opponent: User.IDValue,
		from matchId: Match.IDValue,
		on req: Request
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		req.logger.debug("Removing (\(opponent)) from (\(matchId))")
		guard let session = sessions[matchId] else {
			req.logger.debug("Match (\(matchId)) is not open")
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open"#)
		}

		guard session.game.opponent?.id == opponent else {
			req.logger.debug("User (\(opponent)) is not part of (\(matchId))")
			throw Abort(.badRequest, reason: #"Cannot leave match \#(matchId) you are not a part of"#)
		}

		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.remove(opponent: opponent, on: req) }
			.map { [weak self] _ in
				req.logger.debug("Removed user (\(opponent)) from (\(matchId))")
				self?.sessions[matchId]?.game.opponent = nil
				self?.sessions[matchId]?.host?.webSocket.send(response: .playerLeft(opponent))
				return .ok
			}
	}

	// MARK: Game Flow

	func startMatch(context: WebSocketContext, session: Game.Session) throws {
		context.request.logger.debug("Starting match (\(session.game.id))")
		guard !session.game.hasStarted else {
			context.request.logger.debug("Already started match (\(session.game.id))")
			throw Abort(.internalServerError, reason: #"Cannot start match "\#(session.game.id)" that already started"#)
		}

		Match.find(session.game.id, on: context.request.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMapThrowing { try $0.begin(on: context.request) }
			.whenComplete { result in
				switch result {
				case .success:
					context.request.logger.debug("Started match (\(session.game.id)). Sending state to users")
					let state = GameState(options: session.game.gameOptions)
					session.game.state = state
					session.sendResponseToAll(.state(state))
				case .failure:
					context.request.logger.debug("Failed to start match (\(session.game.id))")
					self.handleServerError(error: .failedToStartMatch, userId: session.game.host.id, session: session)
					if let opponent = session.game.opponent?.id {
						self.handleServerError(error: .failedToStartMatch, userId: opponent, session: session)
					}
				}
			}
	}

	func endMatch(context: WebSocketContext, session: Game.Session) throws {
		context.request.logger.debug("Ending match (\(session.game.id))")
		guard session.game.hasEnded else {
			context.request.logger.debug("Cannot end match (\(session.game.id)) that has not ended")
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(session.game.id)" before game has ended"#)
		}

		sessions[session.game.id] = nil

		Match.find(session.game.id, on: context.request.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMapThrowing { try $0.end(winner: session.game.winner, on: context.request) }
			.whenComplete { result in
				switch result {
				case .success:
					context.request.logger.debug("Successfully ended match (\(session.game.id))")
				case .failure:
					context.request.logger.debug("Failed to end match (\(session.game.id))")
					self.handleServerError(error: .failedToEndMatch, userId: session.game.host.id, session: session)
					if let opponent = session.game.opponent?.id {
						self.handleServerError(error: .failedToEndMatch, userId: opponent, session: session)
					}
				}
			}
	}

	func forfeitMatch(winner: User.IDValue, context: WebSocketContext, session: Game.Session) throws {
		context.request.logger.debug("Forfeiting match (\(session.game.id))")
		guard session.game.hasStarted else {
			context.request.logger.debug("Cannot forfeit match (\(session.game.id))")
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(session.game.id)" before game has ended"#)
		}

		sessions[session.game.id] = nil

		Match.find(session.game.id, on: context.request.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMapThrowing { try $0.end(winner: winner, on: context.request) }
			.whenComplete { result in
				switch result {
				case .success:
					context.request.logger.debug("Successfully forfeit match (\(session.game.id))")
				case .failure:
					context.request.logger.debug("Failed to forfeit match (\(session.game.id))")
					self.handleServerError(error: .failedToEndMatch, userId: session.game.host.id, session: session)
					if let opponent = session.game.opponent?.id {
						self.handleServerError(error: .failedToEndMatch, userId: opponent, session: session)
					}
				}
			}
	}

	@discardableResult
	func delete(match matchId: Match.IDValue, on req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		req.logger.debug("Deleting match (\(matchId))")
		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.delete(on: req.db) }
			.transform(to: .ok)
	}

	@discardableResult
	func updateOptions(
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

	// MARK: WebSocket

	func joinMatch(on req: Request, ws: WebSocket, user: User) throws {
		let userId = try user.requireID()
		let wsContext = WebSocketContext(webSocket: ws, request: req)

		guard let rawMatchId = req.parameters.get(MatchController.Parameter.match.rawValue),
			let matchId = Match.IDValue(uuidString: rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined from path")
		}

		req.logger.debug("Connecting to websocket: user (\(userId)) to (\(matchId))")

		guard sessions[matchId]?.contains(userId) == true else {
			req.logger.debug("Cannot connect user (\(userId)) to (\(matchId))")
			throw Abort(.forbidden, reason: "Cannot connect to a game you are not a part of")
		}

		sessions[matchId]?.add(context: wsContext, forUser: userId)
		sessions[matchId]?.game.playerIsReconnecting(player: userId)

		#warning("FIXME: need to keep clients in sync when one disconnects or encounters error")

		ws.pingInterval = .seconds(30)
		ws.onText { [unowned self] ws, text in
			let reqId = UUID()
			req.logger.debug("[\(reqId)]: \(text)")
			guard let session = self.sessions[matchId] else {
				req.logger.debug(#"Match with ID "\#(matchId)" is not open to play."#)
				return
			}

			guard let context = session.context(forUser: userId) else {
				req.logger.debug("[\(reqId)]: Invalid command")
				ws.send(error: .invalidCommand, fromUser: userId)
				return
			}

			do {
				let message = try GameClientMessage(from: text)
				let resolver = try GameActionResolver(session: session, userId: userId, message: message)
				resolver.resolve { [unowned self] result in
					switch result {
					case .success(let result):
						do {
							try self.handle(result: result, context: context, session: session)
						} catch {
							handle(error: error, userId: userId, session: session)
						}
					case .failure(let error):
						self.handleServerError(error: error, userId: userId, session: session)
					}
				}
			} catch {
				self.handle(error: error, userId: userId, session: session)
			}

			// If the user is rejoining a game in progress, send them commands required to start the game
			if let opponentId = session.game.opponent(for: userId),
				let state = session.game.state,
				!session.game.hasPlayerReconnected(player: userId) {
				session.game.playerDidReconnect(player: userId)
				ws.send(response: .setPlayerReady(userId, true))
				ws.send(response: .setPlayerReady(opponentId, true))
				ws.send(response: .state(state))
			}
		}
	}

	func spectateMatch(on req: Request, ws: WebSocket, user: User) throws {
		let userId = try user.requireID()
		let wsContext = WebSocketContext(webSocket: ws, request: req)

		guard let rawMatchId = req.parameters.get(MatchController.Parameter.match.rawValue),
			let matchId = Match.IDValue(uuidString: rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined from path")
		}

		req.logger.debug("Connecting spectator to websocket: user (\(userId)) to match (\(matchId))")

		guard let session = sessions[matchId] else {
			req.logger.debug("Match (\(matchId)) not open to spectate")
			throw Abort(.badRequest, reason: "Match \(matchId) is not open to spectate")
		}

		guard !session.contains(userId) else {
			req.logger.debug("User (\(userId)) cannot spectate a match they are participating in")
			throw Abort(.badRequest, reason: "Cannot spectate a match you are participating in")
		}

		guard session.game.opponent != nil, session.game.hasStarted else {
			req.logger.debug("Match (\(matchId)) has not started")
			throw Abort(.badRequest, reason: "Cannot spectate a match that has not started")
		}

		guard !session.userIsSpectating(userId: userId) else {
			req.logger.debug("User (\(userId)) already spectating match (\(matchId))")
			throw Abort(.badRequest, reason: "Cannot spectate a match you are already spectating")
		}

		session.addSpectator(context: wsContext, user: userId)
		_ = ws.onClose.always { [weak self] _ in
			self?.sessions[matchId]?.removeSpectator(userId)
		}

		ws.pingInterval = .seconds(30)
		ws.onText { ws, text in
			ws.send(error: .invalidCommand, fromUser: userId)
		}
	}

	// MARK: Resolvers

	private func handle(
		result: GameActionResolver.Result?,
		context: WebSocketContext,
		session: Game.Session
	) throws {
		switch result {
		case .shouldStartMatch:
			try startMatch(context: context, session: session)
		case .shouldEndMatch:
			try endMatch(context: context, session: session)
		case .shouldUpdateOptions:
			try updateOptions(matchId: session.game.id, options: session.game.options, gameOptions: session.game.gameOptions, on: context.request)
		case .shouldForfeitMatch(let winner):
			try forfeitMatch(winner: winner, context: context, session: session)
		case .shouldRemoveOpponent(let user):
			try remove(opponent: user, from: session.game.id, on: context.request)
		case .shouldDeleteMatch:
			sessions[session.game.id] = nil
			try delete(match: session.game.id, on: context.request)
		case .none:
			break
		}
	}

	// MARK: Errors

	private func handleServerError(error: GameServerResponseError, userId: User.IDValue, session: Game.Session) {
		if error.shouldSendToOpponent {
			session.sendErrorToAll(error, fromUser: userId)
		} else {
			session.context(forUser: userId)?.webSocket.send(error: error, fromUser: userId)
		}
	}

	private func handle(error: Error, userId: User.IDValue, session: Game.Session) {
		if let serverError = error as? GameServerResponseError {
			self.handleServerError(error: serverError, userId: userId, session: session)
		} else {
			self.handleServerError(error: .unknownError(nil), userId: userId, session: session)
		}
	}
}
