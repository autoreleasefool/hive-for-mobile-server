//
//  GameManager.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-14.
//

import Vapor
import Combine
import HiveEngine

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
		opponent: User.ID,
		to matchId: Match.ID,
		on conn: DatabaseConnectable
	) throws -> EventLoopFuture<JoinMatchResponse> {
		guard let session = sessions[matchId] else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard session.game.opponentId == nil else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is full"#)
		}

		guard session.game.hostId != opponent else {
			throw Abort(.badRequest, reason: "Cannot join a match you are hosting")
		}

		#warning("TODO: users and moves shouldn't be queried separately -- try to hit DB once")
		return Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.addOpponent(opponent, on: conn) }
			.flatMap {
				User.find(session.game.hostId, on: conn)
					.unwrap(or: Abort(.internalServerError, reason: "Cannot find user with ID \(session.game.hostId)"))
					.and(result: $0)
			}
			.map { [weak self] user, match in
				self?.sessions[matchId]?.game.opponentId = opponent
				self?.sessions[matchId]?.host?.webSocket.send(response: .playerJoined(opponent))
				return try JoinMatchResponse(from: match, withHost: user)
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
		options: Set<GameState.Option>,
		on conn: DatabaseConnectable
	) throws -> EventLoopFuture<HTTPResponseStatus> {
		Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.updateOptions(to: options, on: conn) }
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
						.always { session.host?.webSocket.send(response: .playerLeft(userId)) }
				} catch {
					handle(error: .unknownError(nil), userId: userId, session: session)
				}
			}
		}
	}

	private func setOption(option: GameState.Option, to value: Bool, userId: User.ID, session: GameSession) {
		guard !session.game.hasStarted, let context = session.context(forUser: userId) else {
			return handle(error: .invalidCommand, userId: userId, session: session)
		}

		guard userId == session.game.hostId else {
			return handle(error: .optionNonModifiable, userId: userId, session: session)
		}

		session.game.options.set(option, to: value)
		session.host?.webSocket.send(response: .setOption(option, value))
		session.opponent?.webSocket.send(response: .setOption(option, value))

		do {
			_ = try updateOptions(matchId: session.game.id, options: session.game.options, on: context.request)
		} catch {
			handle(error: .optionValueNotUpdated(option, "\(value)"), userId: userId, session: session)
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
		guard !session.game.hasStarted, session.game.opponentId != nil else {
			return handle(error: .invalidCommand, userId: player, session: session)
		}

		session.game.togglePlayerReady(player: player)

		let readyResponse = GameServerResponse.setPlayerReady(player, session.game.isPlayerReady(player: player))
		session.host?.webSocket.send(response: readyResponse)
		session.opponent?.webSocket.send(response: readyResponse)

		if session.game.hostReady && session.game.opponentReady {
			let state = GameState(options: session.game.options)
			session.game.state = state

			let stateResponse = GameServerResponse.state(state)
			session.host?.webSocket.send(response: stateResponse)
			session.opponent?.webSocket.send(response: stateResponse)
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
