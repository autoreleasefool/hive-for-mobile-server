//
//  MatchPlayController.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import HiveEngine

class MatchPlayController: WebSocketController {

	static let shared = MatchPlayController()

	private init() { }

	private var inProgressMatches: [Match.ID: Match] = [:]
	private var matchGameStates: [Match.ID: GameState] = [:]
	var activeConnections: [User.ID: WebSocketContext] = [:]

	func startGamePlay(match: Match, userId: User.ID, wsContext: WebSocketContext) throws {
		let matchId = try match.requireID()
		register(connection: wsContext, to: userId)

		#warning("TODO: need to keep clients in sync when one disconnects or encounters error")

		wsContext.webSocket.onText { [unowned self] _, text in
			guard let opponentId = match.otherPlayer(from: userId),
				let opponentWSContext = self.activeConnections[opponentId] else {
				return self.handle(
					error: Abort(.internalServerError, reason: #"Opponent in match "\#(matchId)" could not be found"#),
					on: wsContext,
					context: nil
				)
			}

			guard let state = self.matchGameStates[matchId] else {
				return self.handle(
					error: Abort(
						.internalServerError,
						reason: #"GameState for match "\#(matchId)" could not be found"#
					),
					on: wsContext,
					context: nil
				)
			}

			let context = WSClientMatchContext(
				user: userId,
				opponent: opponentId,
				matchId: matchId,
				match: match,
				userWS: wsContext,
				opponentWS: opponentWSContext,
				state: state
			)
			self.handle(text: text, context: context)
		}
	}
}

// MARK: - Message Context

class WSClientMatchContext: WSClientMessageContext {
	let user: User.ID
	let opponent: User.ID?
	let requiredOpponent: User.ID
	let matchId: Match.ID
	let match: Match

	let userWS: WebSocketContext
	let opponentWS: WebSocketContext?
	let requiredOpponentWS: WebSocketContext

	let state: GameState

	init(
		user: User.ID,
		opponent: User.ID,
		matchId: Match.ID,
		match: Match,
		userWS: WebSocketContext,
		opponentWS: WebSocketContext,
		state: GameState
	) {
		self.user = user
		self.opponent = opponent
		self.requiredOpponent = opponent
		self.matchId = matchId
		self.match = match
		self.userWS = userWS
		self.opponentWS = opponentWS
		self.requiredOpponentWS = opponentWS
		self.state = state
	}

	private var isUserHost: Bool {
		user == match.hostId
	}

	private var isHostTurn: Bool {
		(match.hostIsWhite && state.currentPlayer == .white) ||
			(!match.hostIsWhite && state.currentPlayer == .black)
	}

	var isUserTurn: Bool {
		return (isUserHost && isHostTurn) || (!isUserHost && !isHostTurn)
	}

	var matchWinner: User.ID? {
		let winner = state.winner
		if winner.count == 2 {
			return nil
		}

		switch winner.first {
		case .white: return match.hostIsWhite ? match.hostId : match.opponentId
		case .black: return match.hostIsWhite ? match.opponentId : match.hostId
		case .none: return nil
		}
	}
}

extension MatchPlayController {
	func beginMatch(context: WSClientLobbyContext) throws {
		guard let opponent = context.opponent,
			let opponentWS = context.opponentWS else {
			throw Abort(.internalServerError, reason: #"Cannot begin match "\#(context.matchId)" without opponent"#)
		}

		#warning("TODO: wait for the match to begin before continuing")
		_ = try context.match
			.begin(on: context.userWS.request)

		inProgressMatches[context.matchId] = context.match
		matchGameStates[context.matchId] = context.gameState
		try startGamePlay(match: context.match, userId: context.user, wsContext: context.userWS)
		try startGamePlay(match: context.match, userId: opponent, wsContext: opponentWS)
	}

	func endMatch(context: WSClientMatchContext) throws {
		guard context.state.isEndGame else {
			throw Abort(.internalServerError, reason: #"Cannot end match "\#(context.matchId)" before it has ended"#)
		}

		let promise = try context.match
			.end(winner: context.matchWinner, on: context.userWS.request)

		promise.whenSuccess { [unowned self] _ in
			self.inProgressMatches[context.matchId] = nil
			self.matchGameStates[context.matchId] = nil
			self.unregister(userId: context.user)
			self.unregister(userId: context.requiredOpponent)
		}

		promise.whenFailure { [unowned self] in
			self.handle(error: $0, on: context.userWS, context: context)
			self.handle(error: $0, on: context.requiredOpponentWS, context: context)
		}
	}

	func forfeitMatch(context: WSClientMatchContext) throws {
		let promise = try context.match
			.end(winner: context.requiredOpponent, on: context.userWS.request)

		promise.whenSuccess { _ in
			context.userWS.webSocket.send(response: .forfeit(context.user))
			context.requiredOpponentWS.webSocket.send(response: .forfeit(context.user))
		}

		promise.whenFailure { [unowned self] in
			self.handle(error: $0, on: context.userWS, context: context)
		}
	}

	func play(movement: RelativeMovement, with context: WSClientMatchContext) throws {
		guard context.isUserTurn else {
			throw WSServerResponseError.notPlayerTurn
		}

		guard context.state.apply(relativeMovement: movement) else {
			throw WSServerResponseError.invalidMovement(movement.notation)
		}

		let matchMovement = MatchMovement(from: movement, withContext: context)
		let promise = matchMovement.save(on: context.userWS.request)

		promise.whenSuccess { _ in
			context.userWS.webSocket.send(response: .state(context.state))
			context.requiredOpponentWS.webSocket.send(response: .state(context.state))
		}

		promise.whenFailure { [unowned self] in
			self.handle(error: $0, on: context.userWS, context: context)
		}

		guard context.state.isEndGame else { return }
		try endMatch(context: context)
	}
}
