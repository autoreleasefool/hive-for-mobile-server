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

	private let gameManager: GameManager

	init(gameManager: GameManager) {
		self.gameManager = gameManager
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
		return match.save(on: req.db)
			.flatMap {
				do {
					let match = try self.gameManager.add(match, on: req)
					return match
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
			.flatMapThrowing { try Match.Create.Response(from: $0, withHost: user) }
	}

	func join(req: Request) throws -> EventLoopFuture<Match.Join.Response> {
		let user = try req.auth.require(User.self)
		return Match.find(req.parameters.get(Parameter.match.rawValue), on: req.db)
			.unwrap(or: Abort(.notFound))
			.flatMap {
				do {
					let match = try self.gameManager.add(user: user.requireID(), to: $0.requireID(), on: req)
					return match
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

	func open(req: Request) throws -> EventLoopFuture<[Match.Details]> {
		Match.query(on: req.db)
			.join(Match.Host.self, on: \Match.$host.$id == \Match.Host.$id, method: .inner)
			.filter(\.$status == .notStarted)
			.filter(\.$opponent.$id == .none)
			.sort(\.$createdAt)
			.all()
			.flatMapThrowing { matches in
				try matches.map { match in
					var response = try Match.Details(from: match)
					response.host = try User.Summary(from: match.joined(Match.Host.self))
					return response
				}
			}
	}

	func active(req: Request) throws -> EventLoopFuture<[Match.Details]> {
		Match.query(on: req.db)
			.join(Match.Host.self, on: \Match.$host.$id == \Match.Host.$id, method: .inner)
			.join(Match.Opponent.self, on: \Match.$opponent.$id == \Match.Opponent.$id, method: .inner)
			.filter(\.$status == .active)
			.sort(\.$createdAt)
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

	func delete(req: Request) throws -> EventLoopFuture<Void> {
		let matchId = try id(from: req)

		return Match.query(on: req.db)
			.filter(\.$id == matchId)
			.delete()
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

		// Admin authenticated routes
		matches.grouped(AdminMiddleware())
			.group(.parameter(Parameter.match.rawValue)) { match in
			match.delete("delete", use: delete)
		}
	}
}
