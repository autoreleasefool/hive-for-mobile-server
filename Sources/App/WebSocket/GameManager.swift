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

		return Match.find(matchId, on: conn)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.addOpponent(opponent, on: conn) }
			.map { [weak self] in
				self?.sessions[matchId]?.game.opponentId = opponent
				self?.sessions[matchId]?.host?.webSocket.send(response: .playerJoined(opponent))
				return try JoinMatchResponse(from: $0)
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
		#warning("TODO: delete matches")
		return Future.map(on: conn) { .ok }
	}

	func endMatch(context: WebSocketContext, session: GameSession) throws {
		guard session.game.hasEnded, let state = session.game.state else {
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(session.game.id)" before game has ended"#)
		}

		let endingMatch = Match.find(session.game.id, on: context.request)
			.unwrap(or: Abort(.badRequest, reason: "Cannot find match with ID \(session.game.id)"))
			.flatMap { try $0.end(winner: session.game.winner, on: context.request) }

		endingMatch.whenSuccess { [weak self] _ in
			self?.sessions[session.game.id] = nil
		}

		endingMatch.whenFailure { [weak self] in
			self?.handle(error: $0, userId: session.game.hostId, session: session)
			if let opponent = session.game.opponentId {
				self?.handle(error: $0, userId: opponent, session: session)
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

		#warning("TODO: need to keep clients in sync when one disconnects or encounters error")

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
			return handle(error: GameServerResponseError.invalidCommand, userId: userId, session: session)
		}

		if session.game.hasStarted {
			#warning("TODO: forfeit game that has started")
		} else {
			if session.game.hostId == userId {
				sessions[session.game.id] = nil
				session.opponentContext(forUser: userId)?.webSocket.send(response: .playerLeft(userId))
				#warning("TODO: handle error")
				_ = try? delete(match: session.game.id, on: context.request)
			} else {
				#warning("TODO: handle error")
				_ = try? remove(opponent: userId, from: session.game.id, on: context.request)
					.always {
						session.host?.webSocket.send(response: .playerLeft(userId))
					}
			}
		}
	}

	private func setOption(option: GameState.Option, to value: Bool, userId: User.ID, session: GameSession) {
		guard !session.game.hasStarted, let context = session.context(forUser: userId) else {
			return handle(error: GameServerResponseError.invalidCommand, userId: userId, session: session)
		}

		guard userId == session.game.hostId else {
			return handle(error: GameServerResponseError.optionNonModifiable, userId: userId, session: session)
		}

		session.game.options.set(option, to: value)
		session.host?.webSocket.send(response: .setOption(option, value))
		session.opponent?.webSocket.send(response: .setOption(option, value))

		#warning("TODO: handle error")
		_ = try? updateOptions(matchId: session.game.id, options: session.game.options, on: context.request)
	}

	private func sendMessage(message: String, fromUser userId: User.ID, session: GameSession) {
		session.host?.webSocket.send(response: .message(userId, message))
		session.opponent?.webSocket.send(response: .message(userId, message))
	}

	private func playMove(movement: RelativeMovement, fromUser userId: User.ID, session: GameSession) {
		guard session.game.hasStarted,
			let state = session.game.state,
			let context = session.context(forUser: userId) else {
			return handle(error: GameServerResponseError.invalidCommand, userId: userId, session: session)
		}

		guard session.game.isPlayerTurn(player: userId) else {
			return handle(error: GameServerResponseError.notPlayerTurn, userId: userId, session: session)
		}

		guard state.apply(relativeMovement: movement) else {
			return handle(
				error: GameServerResponseError.invalidMovement(movement.notation),
				userId: userId,
				session: session
			)
		}

		let matchMovement = MatchMovement(from: movement, userId: userId, matchId: session.game.id, ordinal: state.move)
		let promise = matchMovement.save(on: context.request)

		promise.whenSuccess { _ in
			session.host?.webSocket.send(response: .state(state))
			session.opponent?.webSocket.send(response: .state(state))
		}

		promise.whenFailure { [weak self] in
			self?.handle(error: $0, userId: userId, session: session)
		}

		guard state.isEndGame else { return }
		#warning("TODO: handle error")
		try? endMatch(context: context, session: session)
	}

	private func togglePlayerReady(player: User.ID, session: GameSession) {
		guard !session.game.hasStarted, session.game.opponentId != nil else {
			return handle(error: GameServerResponseError.invalidCommand, userId: player, session: session)
		}

		session.game.togglePlayerReady(player: player)

		let response = GameServerResponse.setPlayerReady(player, session.game.isPlayerReady(player: player))
		session.host?.webSocket.send(response: response)
		session.opponent?.webSocket.send(response: response)

		if session.game.hostReady && session.game.opponentReady {
			#warning("TODO: start the game")
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
			handle(error: error, userId: userId, session: session)
		}
	}

	private func handle(error: Error, userId: User.ID, session: GameSession) {
		if let serverError = error as? GameServerResponseError {
			session.host?.webSocket.send(error: serverError, fromUser: userId)
			if serverError.shouldSendToOpponent {
				session.opponent?.webSocket.send(error: serverError, fromUser: userId)
			}
		} else {
			session.host?.webSocket.send(error: GameServerResponseError.unknownError(error), fromUser: userId)
		}
	}
}
