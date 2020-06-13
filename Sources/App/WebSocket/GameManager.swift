//
//  GameManager.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Vapor
import Combine
import HiveEngine
import Fluent

final class GameManager {
	private var sessions: [Match.ID: GameSession] = [:]

	init() {
	}

	// MARK: REST

	func add(_ match: Match, on conn: DatabaseConnectable) throws -> EventLoopFuture<Match> {
		guard let matchId = try? match.requireID(), let game = Game(match: match) else {
			throw Abort(.internalServerError, reason: "Cannot add match without ID to GameManager.")
		}

		self.sessions[matchId] = GameSession(game: game)
		return Future.map(on: conn) { match }
	}

	func add(
		user userId: User.ID,
		to matchId: Match.ID,
		on conn: DatabaseConnectable
	) throws -> EventLoopFuture<JoinMatchResponse> {
		guard let session = sessions[matchId] else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard session.game.hostId != userId else {
			return try reconnect(host: userId, to: matchId, session: session, on: conn)
		}

		guard session.game.opponentId == nil || session.game.opponentId == userId else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is full"#)
		}

		return try add(opponentId: userId, to: matchId, session: session, on: conn)
	}

	private func reconnect(
		host: User.ID,
		to matchId: Match.ID,
		session: GameSession,
		on conn: DatabaseConnectable
	) throws -> EventLoopFuture<JoinMatchResponse> {
		#warning("TODO: users and moves shouldn't be queried separately -- try to hit DB once")
		let playerIds: [User.ID] = [session.game.hostId, session.game.opponentId].compactMap { $0 }

		return Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap {
				User.query(on: conn)
					.filter(\.id ~~ playerIds)
					.all()
					.and(result: $0)
			}
			.map { users, match in
				guard let host = users.first(where: { $0.id == session.game.hostId }) else {
					throw Abort(
						.badRequest,
						reason: "Could not find host (\(session.game.hostId))"
					)
				}

				let opponent = users.first(where: { $0.id == session.game.opponentId })
				return try JoinMatchResponse(from: match, withHost: host, withOpponent: opponent)
			}
	}

	private func add(
		opponentId: User.ID,
		to matchId: Match.ID,
		session: GameSession,
		on conn: DatabaseConnectable
	) throws -> EventLoopFuture<JoinMatchResponse> {
		#warning("TODO: users and moves shouldn't be queried separately -- try to hit DB once")
		return Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.addOpponent(opponentId, on: conn) }
			.flatMap {
				User.query(on: conn)
					.filter(\.id ~~ [session.game.hostId, opponentId])
					.all()
					.and(result: $0)
			}
			.map { [weak self] users, match in
				guard let host = users.first(where: { $0.id == session.game.hostId }),
					let opponent = users.first(where: { $0.id == opponentId }) else {
						throw Abort(
							.badRequest,
							reason: "Could not find all users (\(session.game.hostId), \(opponentId))"
						)
				}

				self?.sessions[matchId]?.game.opponentId = opponentId
				self?.sessions[matchId]?.host?.webSocket.send(response: .playerJoined(opponentId))
				return try JoinMatchResponse(from: match, withHost: host, withOpponent: opponent)
			}
	}

	func remove(
		opponent: User.ID,
		from matchId: Match.ID,
		on conn: DatabaseConnectable
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let session = sessions[matchId] else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard session.game.opponentId == opponent else {
			throw Abort(.badRequest, reason: #"Cannot leave match \#(matchId) you are not a part of"#)
		}

		return Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.removeOpponent(opponent, on: conn) }
			.map { [weak self] _ in
				self?.sessions[matchId]?.game.opponentId = nil
				self?.sessions[matchId]?.host?.webSocket.send(response: .playerLeft(opponent))
				return .ok
			}
	}

	func delete(match matchId: Match.ID, on conn: DatabaseConnectable) throws -> EventLoopFuture<HTTPResponseStatus> {
		Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.delete(on: conn) }
			.transform(to: .ok)
	}

	func endMatch(context: WebSocketContext, session: GameSession) throws {
		guard session.game.hasEnded else {
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(session.game.id)" before game has ended"#)
		}

		sessions[session.game.id] = nil

		Match.find(session.game.id, on: context.request)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMap { try $0.end(winner: session.game.winner, on: context.request) }
			.whenFailure { [weak self] _ in
				self?.handle(error: .failedToEndMatch, userId: session.game.hostId, session: session)
				if let opponent = session.game.opponentId {
					self?.handle(error: .failedToEndMatch, userId: opponent, session: session)
				}
			}
	}

	func startMatch(context: WebSocketContext, session: GameSession) throws {
		guard session.game.hasStarted else {
			throw Abort(.internalServerError, reason: #"Cannot start match "\#(session.game.id)" that already started"#)
		}

		Match.find(session.game.id, on: context.request)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMap { try $0.begin(on: context.request) }
			.whenFailure { [weak self] _ in
				self?.handle(error: .failedToStartMatch, userId: session.game.hostId, session: session)
				if let opponent = session.game.opponentId {
					self?.handle(error: .failedToStartMatch, userId: opponent, session: session)
				}
			}
	}

	func forfeitMatch(winner: User.ID, context: WebSocketContext, session: GameSession) throws {
		guard session.game.hasStarted else {
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(session.game.id)" before game has ended"#)
		}

		sessions[session.game.id] = nil

		Match.find(session.game.id, on: context.request)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMap { try $0.end(winner: winner, on: context.request) }
			.whenFailure { [weak self] _ in
				self?.handle(error: .failedToEndMatch, userId: session.game.hostId, session: session)
				if let opponent = session.game.opponentId {
					self?.handle(error: .failedToEndMatch, userId: opponent, session: session)
				}
			}
	}

	func updateOptions(
		matchId: Match.ID,
		options: Set<Match.Option>,
		gameOptions: Set<GameState.Option>,
		on conn: DatabaseConnectable
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.updateOptions(options: options, gameOptions: gameOptions, on: conn) }
			.transform(to: .ok)
	}

	// MARK: WebSocket

	func joinMatch(_ ws: WebSocket, _ request: Request, _ user: User) throws {
		let userId = try user.requireID()
		let wsContext = WebSocketContext(webSocket: ws, request: request)

		guard let rawMatchId = request.parameters.rawValues(for: Match.self).first,
			let matchId = UUID(rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined")
		}

		self.sessions[matchId]?.add(context: wsContext, forUser: userId)

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

			if let opponentId = session.game.opponent(for: userId), let state = session.game.state {
				ws.send(response: .setPlayerReady(opponentId, true))
				ws.send(response: .setPlayerReady(userId, true))
				ws.send(response: .state(state))
			}
		}
	}
}

// MARK: - GameClientMessage

extension GameManager {
	private func forfeit(userId: User.ID, session: GameSession) {
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

	private func setOption(option: GameClientMessage.Option, to value: Bool, userId: User.ID, session: GameSession) {
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

	private func sendMessage(message: String, fromUser userId: User.ID, session: GameSession) {
		session.host?.webSocket.send(response: .message(userId, message))
		session.opponent?.webSocket.send(response: .message(userId, message))
	}

	private func playMove(movement: RelativeMovement, fromUser userId: User.ID, session: GameSession) {
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
		let promise = matchMovement.save(on: context.request)

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

	private func togglePlayerReady(player: User.ID, session: GameSession) {
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
	private func handle(message: GameClientMessage, userId: User.ID, session: GameSession) {
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

	private func handle(text: String, userId: User.ID, session: GameSession) {
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

	private func handle(error: GameServerResponseError, userId: User.ID, session: GameSession) {
		session.host?.webSocket.send(error: error, fromUser: userId)
		if error.shouldSendToOpponent {
			session.opponent?.webSocket.send(error: error, fromUser: userId)
		}
	}
}
