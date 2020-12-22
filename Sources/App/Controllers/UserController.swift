//
//  UserController.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor

struct UserController {
	enum Parameter: String {
		case user = "userID"
	}

	enum Query: String {
		case filter = "filter"
	}

	private func id(from req: Request) throws -> User.IDValue {
		guard let idParam = req.parameters.get(Parameter.user.rawValue),
			let userId = User.IDValue(uuidString: idParam) else {
			throw Abort(.notFound)
		}
		return userId
	}

	// MARK: - Content

	func index(req: Request) throws -> EventLoopFuture<[User.Public.Summary]> {
		User.query(on: req.db)
			.sort(\.$displayName)
			.all()
			.flatMapThrowing { try $0.map { try $0.asPublicSummary() } }
	}

	func summary(req: Request) throws -> EventLoopFuture<User.Public.Summary> {
		User.find(req.parameters.get(Parameter.user.rawValue), on: req.db)
			.unwrap(or: Abort(.notFound))
			.flatMapThrowing { try $0.asPublicSummary() }
	}

	func details(req: Request) throws -> EventLoopFuture<User.Public.Details> {
		let userId = try id(from: req)

		return User.query(on: req.db)
			.with(\.$hostedMatches)
			.with(\.$joinedMatches)
			.filter(\.$id == userId)
			.first()
			.unwrap(or: Abort(.notFound))
			.flatMapThrowing { user in
				var response = try user.asPublicDetails()
				for match in user.allMatches {
					switch match.status {
					case .active: response.activeMatches.append(try match.asPublicDetails())
					case .ended: response.pastMatches.append(try match.asPublicDetails())
					case .notStarted: continue
					}
				}
				return response
			}
	}

	func list(req: Request) throws -> EventLoopFuture<[User.Public.Details]> {
		let filter = try? req.query.get(at: Query.filter.rawValue) ?? ""
		return User.query(on: req.db)
			.with(\.$hostedMatches)
			.with(\.$joinedMatches)
			.filter(\.$displayName ~~ (filter ?? ""))
			.limit(25) // TODO: Remove limiting for user search, add pagination
			.all()
			.flatMapThrowing { users in
				var response: [User.Public.Details] = []
				for user in users {
					guard var userResponse = try? user.asPublicDetails() else { continue }
					for match in user.allMatches {
						switch match.status {
						case .active: userResponse.activeMatches.append(try match.asPublicDetails())
						case .ended: userResponse.pastMatches.append(try match.asPublicDetails())
						case .notStarted: continue
						}
					}
					response.append(userResponse)
				}
				return response
			}
	}

	func logout(req: Request) throws -> EventLoopFuture<User.Logout.Response> {
		guard let token = req.headers.bearerAuthorization?.token else {
			throw Abort(.badRequest, reason: "Token must be supplied to logout")
		}

		return Token.query(on: req.db)
			.filter(\.$value == token)
			.delete()
			.transform(to: User.Logout.Response(success: true))
	}

	func validate(req: Request) throws -> EventLoopFuture<User.Authentication.Response> {
		let user = try req.auth.require(User.self)
		let token = try req.auth.require(Token.self)
		let response = try User.Authentication.Response(accessToken: token.value, user: user.asPublicSummary())
		return req.eventLoop.makeSucceededFuture(response)
	}
}

// MARK: - RouteCollection

extension UserController: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		let users = routes.grouped("api", "users")

		// Public routes

		users.get("all", use: list)
		users.group(.parameter(Parameter.user.rawValue)) { user in
			user.get("details", use: details)
			user.get("summary", use: summary)
		}

		// Protected routes

		let tokenProtected = users
			.grouped(Token.authenticator())
			.grouped(Token.guardMiddleware())
		tokenProtected.delete("logout", use: logout)
		tokenProtected.get("validate", use: validate)

		let adminProtected = users.grouped(AdminMiddleware())
		adminProtected.get(use: index)
	}
}
