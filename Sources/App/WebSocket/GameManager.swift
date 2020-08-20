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

		guard session.game.host.id != userId else {
			return try reconnect(host: userId, to: matchId, session: session, on: req)
		}

		guard session.game.opponent?.id == nil || session.game.opponent?.id == userId else {
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
		Match.query(on: req.db)
			.with(\.$host)
			.with(\.$opponent)
			.filter(\.$id == matchId)
			.first()
			.unwrap(or: Abort(.notFound))
			.flatMapThrowing {
				try Match.Join.Response(from: $0, withHost: $0.host, withOpponent: $0.opponent)
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

		guard session.game.opponent?.id == opponent else {
			throw Abort(.badRequest, reason: #"Cannot leave match \#(matchId) you are not a part of"#)
		}

		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "Cannot find match with ID \(matchId)"))
			.flatMap { $0.remove(opponent: opponent, on: req) }
			.map { [weak self] _ in
				self?.sessions[matchId]?.game.opponent = nil
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
				self.handle(error: .failedToStartMatch, userId: session.game.host.id, session: session)
				if let opponent = session.game.opponent?.id {
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
				self.handle(error: .failedToEndMatch, userId: session.game.host.id, session: session)
				if let opponent = session.game.opponent?.id {
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
				self.handle(error: .failedToEndMatch, userId: session.game.host.id, session: session)
				if let opponent = session.game.opponent?.id {
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

		guard sessions[matchId]?.contains(userId) == true else {
			throw Abort(.forbidden, reason: "Cannot connect to a game you are not a part of")
		}

		sessions[matchId]?.add(context: wsContext, forUser: userId)
		sessions[matchId]?.game.playerIsReconnecting(player: userId)

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

		guard let session = sessions[matchId] else {
			throw Abort(.badRequest, reason: "Match \(matchId) is not open to spectate")
		}

		guard !session.contains(userId) else {
			throw Abort(.badRequest, reason: "Cannot spectate a match you are participating in")
		}

		guard session.game.opponent != nil, session.game.hasStarted else {
			throw Abort(.badRequest, reason: "Cannot spectate a match that has not started")
		}

		guard !session.userIsSpectating(userId: userId) else {
			throw Abort(.badRequest, reason: "Cannot spectate a match you are already spectating")
		}

		session.addSpectator(context: wsContext, user: userId)
		ws.onClose.always { [weak self] _ in self?.sessions[matchId]?.removeSpectator(userId)}
		ws.onText { [weak self] ws, text in
			ws.send(error: .invalidCommand, fromUser: userId)
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

			session.sendResponseToAll(.forfeit(userId))

			do {
				_ = try forfeitMatch(winner: winner, context: context, session: session)
			} catch {
				handle(error: .unknownError(nil), userId: userId, session: session)
			}
		} else {
			if session.game.host.id == userId {
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

		guard userId == session.game.host.id else {
			return handle(error: .optionNonModifiable, userId: userId, session: session)
		}

		session.game.setOption(option, to: value)
		session.sendResponseToAll(.setOption(option.asServerOption, value))

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
		session.sendResponseToAll(.message(userId, message))
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
			session.sendResponseToAll(.state(state))
			if state.hasGameEnded {
				session.sendResponseToAll(.gameOver(session.game.winner))
			}
		}

		promise.whenFailure { [weak self] _ in
			self?.handle(error: .unknownError(nil), userId: userId, session: session)
		}

		guard state.hasGameEnded else { return }
		do {
			try endMatch(context: context, session: session)
		} catch {
			handle(error: .failedToEndMatch, userId: userId, session: session)
		}
	}

	private func togglePlayerReady(player: User.IDValue, session: Game.Session) {
		guard !session.game.hasStarted,
			session.game.opponent?.id != nil,
			let context = session.context(forUser: player) else {
			return handle(error: .invalidCommand, userId: player, session: session)
		}

		session.game.togglePlayerReady(player: player)

		let readyResponse = GameServerResponse.setPlayerReady(player, session.game.isPlayerReady(player: player))
		session.sendResponseToAll(readyResponse)

		guard session.game.host.isReady && session.game.opponent?.isReady == true else {
			return
		}

		let state = GameState(options: session.game.gameOptions)
		session.game.state = state

		session.sendResponseToAll(.state(state))

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
		if error.shouldSendToOpponent {
			session.sendErrorToAll(error, fromUser: userId)
		} else {
			session.context(forUser: userId)?.webSocket.send(error: error, fromUser: userId)
		}
	}
}
