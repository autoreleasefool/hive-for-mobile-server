//
//  LobbyController.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import HiveEngine

class LobbyController: WebSocketController {

	static let shared = LobbyController()

	private init() { }

	private var lobbyMatches: [Match.ID: Match] = [:]
	private var matchOptions: [Match.ID: Set<GameState.Option>] = [:]
	private var readyUsers: Set<User.ID> = []

	var activeConnections: [User.ID: WebSocketContext] = [:]

	func onJoinLobbyMatch(_ ws: WebSocket, _ request: Request, _ user: User) throws {
		let userId = try user.requireID()
		let wsContext = WebSocketContext(webSocket: ws, request: request)
		register(connection: wsContext, to: userId)

		guard let rawMatchId = request.parameters.rawValues(for: Match.self).first,
			let matchId = UUID(rawMatchId) else {
			throw Abort(.badRequest, reason: "Match ID could not be determined")
		}

		guard lobbyMatches[matchId] != nil else {
			throw Abort(.badRequest, reason: #"Match with ID "\#(matchId)" could not be found"#)
		}

		#warning("TODO: need to keep clients in sync when one disconnects or encounters error")

		ws.onText { [unowned self] _, text in
			guard let match = self.lobbyMatches[matchId] else {
				return self.handle(
					error: Abort(.badRequest, reason: #"Match with ID "\#(matchId)" could not be found"#),
					on: wsContext,
					context: nil
				)
			}

			guard let options = self.matchOptions[matchId] else {
				return self.handle(
					error: Abort(
						.badRequest,
						reason: #"Could not find Set<GameState.Option> for match "\#(matchId)""#
					),
					on: wsContext,
					context: nil
				)
			}

			let opponentId = match.otherPlayer(from: userId)
			let opponentWSContext: WebSocketContext?
			if let opponentId = opponentId {
				opponentWSContext = self.activeConnections[opponentId]
			} else {
				opponentWSContext = nil
			}

			let context = WSClientLobbyContext(
				user: userId,
				opponent: opponentId,
				matchId: matchId,
				match: match,
				userWS: wsContext,
				opponentWS: opponentWSContext,
				options: options
			)
			self.handle(text: text, context: context)
		}
	}
}

// MARK: - Message Context

class WSClientLobbyContext: WSClientMessageContext {
	let user: User.ID
	let opponent: User.ID?
	let matchId: Match.ID
	let match: Match

	let userWS: WebSocketContext
	let opponentWS: WebSocketContext?

	var options: Set<GameState.Option>

	var gameState: GameState {
		return GameState(options: options)
	}

	init(
		user: User.ID,
		opponent: User.ID?,
		matchId: Match.ID,
		match: Match,
		userWS: WebSocketContext,
		opponentWS: WebSocketContext?,
		options: Set<GameState.Option>
	) {
		self.user = user
		self.opponent = opponent
		self.matchId = matchId
		self.match = match
		self.userWS = userWS
		self.opponentWS = opponentWS
		self.options = options
	}
}

// MARK: - REST

extension LobbyController {
	func open(match: Match, on conn: DatabaseConnectable) throws -> Future<Match> {
		let matchId = try match.requireID()
		guard lobbyMatches[matchId] == nil else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" already in lobby"#)
		}

		return try match.begin(on: conn)
			.map { [unowned self] match in
				self.lobbyMatches[matchId] = match
				self.matchOptions[matchId] = match.gameOptions
				return match
			}
	}

	func add(
		opponent: User.ID,
		to matchId: Match.ID,
		on conn: DatabaseConnectable
	) throws -> Future<JoinMatchResponse> {
		guard let match = lobbyMatches[matchId] else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is not open to join"#)
		}

		guard match.opponentId == nil else {
			throw Abort(.badRequest, reason: #"Match \#(matchId) is full"#)
		}

		guard match.hostId != opponent else {
			throw Abort(.badRequest, reason: "Cannot join a match you are hosting")
		}

		return match.addOpponent(opponent, on: conn)
			.map { try JoinMatchResponse(from: $0) }
	}

	func readyPlayer(_ context: WSClientLobbyContext) throws {
		if context.opponent != nil {
			readyUsers.set(context.user, to: !readyUsers.contains(context.user))
		}

		let response = WSServerResponse.setPlayerReady(context.user, readyUsers.contains(context.user))
		context.userWS.webSocket.send(response: response)
		context.opponentWS?.webSocket.send(response: response)

		if let opponent = context.opponent,
			readyUsers.contains(context.user) && readyUsers.contains(opponent) {
			removeFromLobby(context: context)
			try MatchPlayController.shared.beginMatch(context: context)
		}
	}

	private func removeFromLobby(context: WSClientMessageContext) {
		lobbyMatches[context.matchId] = nil
		matchOptions[context.matchId] = nil
		unregister(userId: context.user)
		readyUsers.remove(context.user)
		if let opponent = context.opponent {
			unregister(userId: opponent)
			readyUsers.remove(opponent)
		}
	}
}
