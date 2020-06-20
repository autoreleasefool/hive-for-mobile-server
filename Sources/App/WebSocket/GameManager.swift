//
//  GameManager.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Combine
import Fluent
import HiveEngine
import Vapor

final class GameManager {
	private var sessions: [Match.IDValue: Game.Session] = [:]

	init() {}

	// MARK: Managing Players

	func add(_ match: Match, on req: Request) throws -> EventLoopFuture<Match> {
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
		guard let session = sessions[matchId] else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard session.game.hostId != userId else {
			return try reconnect(host: userId, to: matchId, session: session, on: req)
		}

		guard session.game.opponentId == nil || session.game.opponentId == userId else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is full"#)
		}

		return try add(opponentId: userId, to: matchId, session: session, on: req)
	}

	private func reconnect(
		host: User.IDValue,
		to matchId: Match.IDValue,
		session: Game.Session,
		on req: Request
	) throws -> EventLoopFuture<Match.Join.Response> {
		#warning("TODO: users and moves shouldn't be queried separately -- try to hit DB once")
		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap {
				User.query(on: req.db)
					.filter(\.$id ~~ [session.game.hostId, session.game.opponentId].compactMap { $0 })
					.all()
					.and(value: $0)
			}
			.flatMapThrowing { users, match in
				guard let host = users.first(where: { $0.id == session.game.hostId }) else {
					throw Abort(
						.badRequest,
						reason: "Could not find host (\(session.game.hostId))"
					)
				}

				let opponent = users.first(where: { $0.id == session.game.opponentId })
				return try Match.Join.Response(from: match, withHost: host, withOpponent: opponent)
			}
	}

	private func add(
		opponentId: User.IDValue,
		to matchId: Match.IDValue,
		session: Game.Session,
		on req: Request
	) throws -> EventLoopFuture<Match.Join.Response> {
		#warning("TODO: users and moves shouldn't be queried separately -- try to hit DB once")
		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.add(opponent: opponentId, on: req) }
			.flatMap {
				User.query(on: req.db)
					.filter(\.$id ~~ [session.game.hostId, opponentId])
					.all()
					.and(value: $0)
			}
			.flatMapThrowing { users, match in
				guard let host = users.first(where: { $0.id == session.game.hostId }),
					let opponent = users.first(where: { $0.id == opponentId }) else {
						throw Abort(
							.badRequest,
							reason: "Could not find all users (\(session.game.hostId), \(opponentId))"
						)
				}

				self.sessions[matchId]?.game.opponentId = opponentId
				self.sessions[matchId]?.host?.webSocket.send(response: .playerJoined(opponentId))
				return try Match.Join.Response(from: match, withHost: host, withOpponent: opponent)
			}
	}

	func remove(
		opponent: User.IDValue,
		from matchId: Match.IDValue,
		on req: Request
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let session = sessions[matchId] else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard session.game.opponentId == opponent else {
			throw Abort(.badRequest, reason: #"Cannot leave match \#(matchId) you are not a part of"#)
		}

		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.remove(opponent: opponent, on: req) }
			.map { [weak self] _ in
				self?.sessions[matchId]?.game.opponentId = nil
				self?.sessions[matchId]?.host?.webSocket.send(response: .playerLeft(opponent))
				return .ok
			}
	}

	// MARK: Game Flow

	func startMatch(context: WebSocketContext, session: Game.Session) throws {
		guard !session.game.hasStarted else {
			throw Abort(.internalServerError, reason: #"Cannot start match "\#(session.game.id)" that already started"#)
		}

		Match.find(session.game.id, on: context.request.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMapThrowing { try $0.begin(on: context.request).wait() }
			.whenFailure { _ in
				self.handle(error: .failedToStartMatch, userId: session.game.hostId, session: session)
				if let opponent = session.game.opponentId {
					self.handle(error: .failedToStartMatch, userId: opponent, session: session)
				}
			}
	}

	func endMatch(context: WebSocketContext, session: Game.Session) throws {
		guard session.game.hasEnded else {
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(session.game.id)" before game has ended"#)
		}

		sessions[session.game.id] = nil

		Match.find(session.game.id, on: context.request.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMapThrowing { try $0.end(winner: session.game.winner, on: context.request).wait() }
			.whenFailure { _ in
				self.handle(error: .failedToEndMatch, userId: session.game.hostId, session: session)
				if let opponent = session.game.opponentId {
					self.handle(error: .failedToEndMatch, userId: opponent, session: session)
				}
			}
	}

	func forfeitMatch(winner: User.IDValue, context: WebSocketContext, session: Game.Session) throws {
		guard session.game.hasStarted else {
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(session.game.id)" before game has ended"#)
		}

		sessions[session.game.id] = nil

		Match.find(session.game.id, on: context.request.db)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMapThrowing { try $0.end(winner: winner, on: context.request).wait() }
			.whenFailure { _ in
				self.handle(error: .failedToEndMatch, userId: session.game.hostId, session: session)
				if let opponent = session.game.opponentId {
					self.handle(error: .failedToEndMatch, userId: opponent, session: session)
				}
			}
	}

	func delete(match matchId: Match.IDValue, on req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.delete(on: req.db) }
			.transform(to: .ok)
	}

	func updateOptions(
		matchId: Match.IDValue,
		options: Set<Match.Option>,
		gameOptions: Set<GameState.Option>,
		on req: Request
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		Match.find(matchId, on: req.db)
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

		sessions[matchId]?.add(context: wsContext, forUser: userId)

		#warning("FIXME: need to keep clients in sync when one disconnects or encounters error")

		ws.onText { [weak self] ws, text in
			guard let session = self?.sessions[matchId] else {
				print(#"Match with ID "\#(matchId)" is not open to play."#)
				return
			}

			guard session.contains(userId) else {
				ws.send(error: .invalidCommand, fromUser: userId)
				return
			}

			self?.handle(text: text, userId: userId, session: session)

			// If the user is rejoining a game in progress, send them commands required to start the game
			if let opponentId = session.game.opponent(for: userId), let state = session.game.state {
				ws.send(response: .setPlayerReady(userId, true))
				ws.send(response: .setPlayerReady(opponentId, true))
				ws.send(response: .state(state))
			}
		}
	}
}

// MARK: - GameClientMessage

extension GameManager {
	private func forfeit(userId: User.IDValue, session: Game.Session) {
		guard let context = session.context(forUser: userId) else {
			return handle(error: .invalidCommand, userId: userId, session: session)
		}

		if session.game.hasStarted {
			guard let winner = session.game.opponent(for: userId) else {
				return handle(error: .invalidCommand, userId: userId, session: session)
			}

			session.host?.webSocket.send(response: .forfeit(userId))
			session.opponent?.webSocket.send(response: .forfeit(userId))

			do {
				_ = try forfeitMatch(winner: winner, context: context, session: session)
			} catch {
				handle(error: .unknownError(nil), userId: userId, session: session)
			}
		} else {
			if session.game.hostId == userId {
				sessions[session.game.id] = nil
				session.opponentContext(forUser: userId)?.webSocket.send(response: .playerLeft(userId))

				do {
					_ = try delete(match: session.game.id, on: context.request)
				} catch {
					handle(error: .unknownError(nil), userId: userId, session: session)
				}
			} else {
				do {
					_ = try remove(opponent: userId, from: session.game.id, on: context.request)
				} catch {
					handle(error: .unknownError(nil), userId: userId, session: session)
				}
			}
		}
	}

	private func setOption(
		option: GameClientMessage.Option,
		to value: Bool,
		userId: User.IDValue,
		session: Game.Session
	) {
		guard !session.game.hasStarted, let context = session.context(forUser: userId) else {
			return handle(error: .invalidCommand, userId: userId, session: session)
		}

		guard userId == session.game.hostId else {
			return handle(error: .optionNonModifiable, userId: userId, session: session)
		}

		session.game.setOption(option, to: value)
		session.host?.webSocket.send(response: .setOption(option.asServerOption, value))
		session.opponent?.webSocket.send(response: .setOption(option.asServerOption, value))

		do {
			_ = try updateOptions(
				matchId: session.game.id,
				options: session.game.options,
				gameOptions: session.game.gameOptions,
				on: context.request
			)
		} catch {
			handle(error: .optionValueNotUpdated(option.asServerOption, "\(value)"), userId: userId, session: session)
		}
	}

	private func sendMessage(message: String, fromUser userId: User.IDValue, session: Game.Session) {
		session.host?.webSocket.send(response: .message(userId, message))
		session.opponent?.webSocket.send(response: .message(userId, message))
	}

	private func playMove(movement: RelativeMovement, fromUser userId: User.IDValue, session: Game.Session) {
		guard session.game.hasStarted,
			let state = session.game.state,
			let context = session.context(forUser: userId) else {
			return handle(error: .invalidCommand, userId: userId, session: session)
		}

		guard session.game.isPlayerTurn(player: userId) else {
			return handle(error: .notPlayerTurn, userId: userId, session: session)
		}

		guard state.apply(relativeMovement: movement) else {
			return handle(
				error: .invalidMovement(movement.notation),
				userId: userId,
				session: session
			)
		}

		let matchMovement = MatchMovement(from: movement, userId: userId, matchId: session.game.id, ordinal: state.move)
		let promise = matchMovement.save(on: context.request.db)

		promise.whenSuccess { _ in
			session.host?.webSocket.send(response: .state(state))
			session.opponent?.webSocket.send(response: .state(state))
			if state.isEndGame {
				session.host?.webSocket.send(response: .gameOver(session.game.winner))
				session.opponent?.webSocket.send(response: .gameOver(session.game.winner))
			}
		}

		promise.whenFailure { [weak self] _ in
			self?.handle(error: .unknownError(nil), userId: userId, session: session)
		}

		guard state.isEndGame else { return }
		do {
			try endMatch(context: context, session: session)
		} catch {
			handle(error: .failedToEndMatch, userId: userId, session: session)
		}
	}

	private func togglePlayerReady(player: User.IDValue, session: Game.Session) {
		guard !session.game.hasStarted,
			session.game.opponentId != nil,
			let context = session.context(forUser: player) else {
			return handle(error: .invalidCommand, userId: player, session: session)
		}

		session.game.togglePlayerReady(player: player)

		let readyResponse = GameServerResponse.setPlayerReady(player, session.game.isPlayerReady(player: player))
		session.host?.webSocket.send(response: readyResponse)
		session.opponent?.webSocket.send(response: readyResponse)

		guard session.game.hostReady && session.game.opponentReady else {
			return
		}

		let state = GameState(options: session.game.gameOptions)
		session.game.state = state

		session.host?.webSocket.send(response: .state(state))
		session.opponent?.webSocket.send(response: .state(state))

		do {
			try startMatch(context: context, session: session)
		} catch {
			handle(error: .unknownError(nil), userId: player, session: session)
		}
	}
}

// MARK: - Messages

extension GameManager {
	private func handle(message: GameClientMessage, userId: User.IDValue, session: Game.Session) {
		switch message {
		case .playerReady:
			togglePlayerReady(player: userId, session: session)
		case .playMove(let movement):
			playMove(movement: movement, fromUser: userId, session: session)
		case .sendMessage(let string):
			sendMessage(message: string, fromUser: userId, session: session)
		case .setOption(let option, let value):
			setOption(option: option, to: value, userId: userId, session: session)
		case .forfeit:
			forfeit(userId: userId, session: session)
		}
	}

	private func handle(text: String, userId: User.IDValue, session: Game.Session) {
		do {
			let message = try GameClientMessage(from: text)
			handle(message: message, userId: userId, session: session)
		} catch {
			if let serverError = error as? GameServerResponseError {
				handle(error: serverError, userId: userId, session: session)
			} else {
				handle(error: .unknownError(nil), userId: userId, session: session)
			}
		}
	}

	private func handle(error: GameServerResponseError, userId: User.IDValue, session: Game.Session) {
		session.host?.webSocket.send(error: error, fromUser: userId)
		if error.shouldSendToOpponent {
			session.opponent?.webSocket.send(error: error, fromUser: userId)
		}
	}
}
