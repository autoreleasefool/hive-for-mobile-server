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

	private func id(from req: Request) throws -> Match.IDValue {
		guard let idParam = req.parameters.get(Parameter.match.rawValue),
			let matchId = Match.IDValue(uuidString: idParam) else {
			throw Abort(.notFound)
		}
		return matchId
	}

	// MARK: Modify

	func create(req: Request) throws -> EventLoopFuture<Match.Create.Response> {
		let user = try req.auth.require(User.self)
		let match = try Match(withHost: user)
		req.logger.debug("Creating match with host \(String(describing: user.id))")
		return match.save(on: req.db)
			.flatMap {
				do {
					let state = try Game.State(match: match)
					let game = Game(state: state)
					return try req.application
						.gameService
						.addGame(game, on: req)
						.map { match }
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
			.flatMapThrowing { try Match.Create.Response(from: $0, withHost: user) }
	}

	func join(req: Request) throws -> EventLoopFuture<Match.Join.Response> {
		let user = try req.auth.require(User.self)
		req.logger.debug("User (\(String(describing: user.id))) joining match")

		guard let matchParam = req.parameters.get(Parameter.match.rawValue),
			let matchId = Match.IDValue(uuidString: matchParam) else {
			return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "ID is not valid"))
		}

		return Match.query(on: req.db)
			.filter(\.$id == matchId)
			.with(\.$host)
			.with(\.$opponent)
			.first()
			.unwrap(or: Abort(.notFound))
			.flatMap { match in
				do {
					return try req.application
						.gameService
						.addUser(user, to: match, on: req)
						.flatMapThrowing { try Match.Join.Response(from: match, withHost: match.host, withOpponent: user) }
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
	}

	// MARK: Details

	func details(req: Request) throws -> EventLoopFuture<Match.Details> {
		let matchId = try id(from: req)

		return Match.query(on: req.db)
			.with(\.$host)
			.with(\.$opponent)
			.with(\.$winner)
			.with(\.$moves)
			.filter(\.$id == matchId)
			.first()
			.unwrap(or: Abort(.notFound))
			.flatMapThrowing {
				var response = try Match.Details(from: $0)
				response.host = try User.Summary(from: $0.host)
				if let opponent = $0.opponent {
					response.opponent = try User.Summary(from: opponent)
				}
				if let winner = $0.winner {
					response.winner = try User.Summary(from: winner)
				}
				response.moves = try $0.moves.map { try MatchMovement.Summary(from: $0) }
				return response
			}
	}

	func listOpen(req: Request) throws -> EventLoopFuture<[Match.Details]> {
		Match.query(on: req.db)
			.join(Match.Host.self, on: \Match.$host.$id == \Match.Host.$id, method: .inner)
			.filter(\.$status == .notStarted)
			.filter(\.$opponent.$id == .none)
			.sort(\.$createdAt, .descending)
			.all()
			.flatMapThrowing { matches in
				try matches.map { match in
					var response = try Match.Details(from: match)
					response.host = try User.Summary(from: match.joined(Match.Host.self))
					return response
				}
			}
	}

	func listActive(req: Request) throws -> EventLoopFuture<[Match.Details]> {
		Match.query(on: req.db)
			.join(Match.Host.self, on: \Match.$host.$id == \Match.Host.$id, method: .inner)
			.join(Match.Opponent.self, on: \Match.$opponent.$id == \Match.Opponent.$id, method: .inner)
			.filter(\.$status == .active)
			.sort(\.$createdAt, .descending)
			.all()
			.flatMapThrowing { matches in
				try matches.map { match in
					var response = try Match.Details(from: match)
					response.host = try User.Summary(from: match.joined(Match.Host.self))
					response.opponent = try User.Summary(from: match.joined(Match.Opponent.self))
					return response
				}
			}
	}

	func delete(req: Request) throws -> EventLoopFuture<Match.Delete.Response> {
		let matchId = try id(from: req)
		return Match.find(matchId, on: req.db)
			.unwrap(or: Abort(.notFound))
			.flatMap { $0.delete(on: req.db) }
			.map { Match.Delete.Response(success: true) }
	}
}

// MARK: - RouteCollection

extension MatchController: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		let matches = routes.grouped("api", "matches")

		// Public routes
		matches.get("open", use: listOpen)
		matches.get("active", use: listActive)
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

		// Admin authenticated routes
		tokenProtected.grouped(AdminMiddleware())
			.group(.parameter(Parameter.match.rawValue)) { match in
			match.delete("delete", use: delete)
		}
	}
}
