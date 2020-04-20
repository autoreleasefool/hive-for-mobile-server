//
//  MatchController.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import Fluent
import FluentSQLite
import Crypto

final class MatchController {
	private let gameManager: GameManager

	init(gameManager: GameManager) {
		self.gameManager = gameManager
	}

	func create(_ request: Request) throws -> Future<CreateMatchResponse> {
		let user = try request.requireAuthenticated(User.self)
		let match = try Match(withHost: user)
		return match.save(on: request)
			.flatMap { try self.gameManager.add($0, on: request) }
			.map {  try CreateMatchResponse(from: $0, withHost: user) }
	}

	func details(_ request: Request) throws -> Future<MatchDetailsResponse> {
		#warning("TODO: users and moves shouldn't be queried separately -- try to hit DB once")
		return try request.parameters.next(Match.self)
			.flatMap {
				try $0.moves
					.query(on: request)
					.sort(\.ordinal)
					.all()
					.and(result: $0)
			}
			.flatMap { moves, match in
				User.query(on: request)
					.filter(\.id ~~ [match.hostId, match.opponentId])
					.all()
					.and(result: moves)
					.and(result: match)
			}.map { usersAndMoves, match in
				let (users, moves) = usersAndMoves
				var response = try MatchDetailsResponse(from: match)
				response.moves = try moves.map { try MatchMovementResponse(from: $0) }
				for user in users {
					if user.id == match.hostId {
						response.host = try UserSummaryResponse(from: user)
					} else if user.id == match.opponentId {
						response.opponent = try UserSummaryResponse(from: user)
					}

					if user.id == match.winner {
						response.winner = try UserSummaryResponse(from: user)
					}
				}
				return response
			}
	}

	func openMatches(_ request: Request) throws -> Future<[MatchDetailsResponse]> {
		#warning("TODO: users shouldn't be queried separately -- try to hit DB once")
		return Match.query(on: request)
			.filter(\.status == .notStarted)
			.filter(\.opponentId == .none)
			.sort(\.createdAt)
			.all()
			.flatMap {
				User.query(on: request)
					.all()
					.and(result: $0)
			}.map { users, matches in
				try matches.map { match in
					var response = try MatchDetailsResponse(from: match)
					for user in users {
						if match.hostId == user.id {
							response.host = try UserSummaryResponse(from: user)
						} else if match.opponentId == user.id {
							response.opponent = try UserSummaryResponse(from: user)
						}

						if match.winner == user.id {
							response.winner = try UserSummaryResponse(from: user)
						}
					}
					return response
				}
			}
	}

	func activeMatches(_ request: Request) throws -> Future<[MatchDetailsResponse]> {
		Match.query(on: request)
			.filter(\.status == .active)
			.sort(\.createdAt)
			.all()
			.map { try $0.map { try MatchDetailsResponse(from: $0) } }
	}

	func joinMatch(_ request: Request) throws -> Future<JoinMatchResponse> {
		let user = try request.requireAuthenticated(User.self)
		return try request.parameters.next(Match.self)
			.flatMap { match in
				try self.gameManager.add(opponent: user.requireID(), to: match.requireID(), on: request)
			}
	}
}

// MARK: RouteCollection

extension MatchController: RouteCollection {
	func boot(router: Router) throws {
		let matchGroup = router.grouped("matches")

		// Public routes
		matchGroup.get("open", use: openMatches)
		matchGroup.get("active", use: activeMatches)
		matchGroup.get(Match.parameter, use: details)

		// Token authenticated routes
		let tokenMatchGroup = matchGroup.grouped(User.tokenAuthMiddleware())
		tokenMatchGroup.post(Match.parameter, "join", use: joinMatch)
		tokenMatchGroup.post("new", use: create)
	}
}
