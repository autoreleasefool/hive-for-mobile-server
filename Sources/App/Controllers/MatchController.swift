//
//  MatchController.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor

final class MatchController {
	enum Parameter: String {
		case match = "matchID"
	}

//	private let gameManager: GameManager
//
//	init(gameManager: GameManager) {
//		self.gameManager = gameManager
//	}

	// MARK: Modify

	func create(req: Request) throws -> EventLoopFuture<Match.Create.Response> {
		let user = try req.auth.require(User.self)
		let match = try Match(withHost: user)
		return match.save(on: req.db)
//			.flatMap { try self.gameManager.add($0, on: request) }
			.flatMapThrowing { try Match.Create.Response(from: match, withHost: user) }
	}

	func join(req: Request) throws -> EventLoopFuture<Match.Join.Response> {
		let user = try req.auth.require(User.self)
		return Match.find(req.parameters.get(Parameter.match.rawValue), on: req.db)
			.unwrap(or: Abort(.notFound))
//			.flatMapThrowing {
//				try self.gameManager.add(user: user.requireID(), to: $0.requireID(), on: req)
//			}
			.flatMapThrowing { try Match.Join.Response(from: $0) }
	}

	// MARK: Details

	func details(req: Request) throws -> EventLoopFuture<Match.Details> {
		#warning("TODO: users and moves shouldn't be queried separately -- try to hit DB once")

		return Match.find(req.parameters.get(Parameter.match.rawValue), on: req.db)
			.unwrap(or: Abort(.notFound))
			.flatMap {
				$0.$moves.query(on: req.db)
					.sort(\.$ordinal)
					.all()
					.and(value: $0)
			}
			.flatMap { moves, match in
				User.query(on: req.db)
					.filter(\.$id ~~ [match.hostId, match.opponentId].compactMap { $0 })
					.all()
					.and(value: moves)
					.and(value: match)
			}
			.flatMapThrowing { usersAndMoves, match in
				let (users, moves) = usersAndMoves
				var response = try Match.Details(from: match)
				response.moves = try moves.map { try MatchMovement.Summary(from: $0) }
				for user in users {
					if user.id == match.hostId {
						response.host = try User.Summary(from: user)
					} else if user.id == match.opponentId {
						response.opponent = try User.Summary(from: user)
					}

					if user.id == match.winner {
						response.winner = try User.Summary(from: user)
					}
				}
				return response
			}
	}

	func open(req: Request) throws -> EventLoopFuture<[Match.Details]> {
		#warning("TODO: users shouldn't be queried separately -- try to hit DB once")
		return Match.query(on: req.db)
			.filter(\.$status == .notStarted)
			.filter(\.$opponentId == .none)
			.sort(\.$createdAt)
			.all()
			.toDetails(req: req)
	}

	func active(req: Request) throws -> EventLoopFuture<[Match.Details]> {
		#warning("TODO: users shouldn't be queried separately -- try to hit DB once")
		return Match.query(on: req.db)
			.filter(\.$status == .active)
			.sort(\.$createdAt)
			.all()
			.toDetails(req: req)
	}
}

// MARK: - Match.Details

private extension EventLoopFuture where Value == [Match] {
	func toDetails(req: Request) -> EventLoopFuture<[Match.Details]> {
		self.flatMap {
				User.query(on: req.db)
					.all()
					.and(value: $0)
			}
			.flatMapThrowing { users, matches in
				try matches.map { match in
					var response = try Match.Details(from: match)
					for user in users {
						if match.hostId == user.id {
							response.host = try User.Summary(from: user)
						} else if match.opponentId == user.id {
							response.opponent = try  User.Summary(from: user)
						}

						if match.winner == user.id {
							response.winner = try  User.Summary(from: user)
						}
					}
					return response
				}
			}
	}
}

// MARK: - RouteCollection

extension MatchController: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		let matches = routes.grouped("api", "matches")

		// Public routes
		matches.get("open", use: open)
		matches.get("active", use: active)
		matches.group(.parameter(Parameter.match.rawValue)) { match in
			match.get("details", use: details)
		}

		// Token authenticated routes
		let tokenProtected = matches
			.grouped(Token.authenticator())
			.grouped(Token.guardMiddleware())
		tokenProtected.post("new", use: create)
		tokenProtected.group(.parameter(Parameter.match.rawValue)) { match in
			match.post("join", use: join)
		}

	}
}
