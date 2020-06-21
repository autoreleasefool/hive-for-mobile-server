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

	// MARK: - Content

	func index(req: Request) throws -> EventLoopFuture<[User.Summary]> {
		User.query(on: req.db)
			.sort(\.$displayName)
			.all()
			.flatMapThrowing { try $0.map { try User.Summary(from: $0) } }
	}

	func summary(req: Request) throws -> EventLoopFuture<User.Summary> {
		User.find(req.parameters.get(Parameter.user.rawValue), on: req.db)
			.unwrap(or: Abort(.notFound))
			.flatMapThrowing { try User.Summary(from: $0) }
	}

	func details(req: Request) throws -> EventLoopFuture<User.Details> {
		User.find(req.parameters.get(Parameter.user.rawValue), on: req.db)
			.unwrap(or: Abort(.notFound))
			.flatMap {
				Match.query(on: req.db)
					.filter(\.$status ~~ [.active, .ended])
					.sort(\.$createdAt)
					.all()
					.and(value: $0)
			}
			.flatMapThrowing { matches, user in
				#warning("TODO: need to add users/winners to Match.Details")
				var response = try User.Details(from: user)
				for match in matches {
					guard match.hostId == user.id || match.opponentId == user.id else { continue }
					if match.status == .active {
						response.activeMatches.append(try Match.Details(from: match))
					} else if match.status == .ended {
						response.pastMatches.append(try Match.Details(from: match))
					}
				}
				return response
			}
	}

	// MARK: - Authentication

	func create(req: Request) throws -> EventLoopFuture<User.Create.Response> {
		try User.Create.validate(req)
		let create = try req.content.decode(User.Create.self)

		guard create.password == create.verifyPassword else {
			throw Abort(.badRequest, reason: "Password and verification must match.")
		}

		return User.query(on: req.db)
			.filter(\.$email == create.email.lowercased())
			.first()
			.flatMap { existingUser -> EventLoopFuture<User> in
				guard existingUser == nil else {
					return req.eventLoop.makeFailedFuture(
						Abort(.badRequest, reason: "User with email already exists.")
					)
				}

				do {
					let hash = try Bcrypt.hash(create.password)
					let user = User(email: create.email.lowercased(), password: hash, displayName: create.displayName)
					return user.save(on: req.db)
						.map { user }
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
			.flatMap { user in
				do {
					let token = try Token.generateToken(forUser: user.requireID(), source: .signup)
					return token.save(on: req.db)
						.map { (user, token) }
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
			.flatMapThrowing { (user, token) in
				try User.Create.Response(from: user, withToken: token)
			}
	}

	func login(req: Request) throws -> EventLoopFuture<SessionToken> {
		let user = try req.auth.require(User.self)
		let token = try Token.generateToken(forUser: user.requireID(), source: .login)
		return token.save(on: req.db)
			.flatMapThrowing { try SessionToken(user: user, token: token) }
	}

	func logout(req: Request) throws -> EventLoopFuture<HTTPResponseStatus> {
		guard let token = req.headers.bearerAuthorization?.token else {
			throw Abort(.badRequest, reason: "Token must be supplied to logout")
		}

		return Token.query(on: req.db)
			.filter(\.$value == token)
			.delete()
			.transform(to: .ok)
	}

	func validate(req: Request) throws -> EventLoopFuture<SessionToken> {
		let user = try req.auth.require(User.self)
		let token = try req.auth.require(Token.self)
		let session = try SessionToken(user: user, token: token)
		return req.eventLoop.makeSucceededFuture(session)
	}
}

// MARK: - RouteCollection

extension UserController: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		let users = routes.grouped("api", "users")

		// Public routes

		users.post("signup", use: create)
		users.group(.parameter(Parameter.user.rawValue)) { user in
			user.get("details", use: details)
			user.get("summary", use: summary)
		}

		// Protected routes

		let passwordProtected = users
			.grouped(User.authenticator())
			.grouped(User.guardMiddleware())
		passwordProtected.post("login", use: login)

		let tokenProtected = users
			.grouped(Token.authenticator())
			.grouped(Token.guardMiddleware())
		tokenProtected.delete("logout", use: logout)
		tokenProtected.get("validate", use: validate)

		#warning("TODO: remove, or guard behind admin")
		let adminProtected = users.grouped(AdminMiddleware())
		adminProtected.get(use: index)
	}
}
