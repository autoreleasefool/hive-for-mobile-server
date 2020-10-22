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
		let userId = try id(from: req)

		return User.query(on: req.db)
			.with(\.$hostedMatches)
			.with(\.$joinedMatches)
			.filter(\.$id == userId)
			.first()
			.unwrap(or: Abort(.notFound))
			.flatMapThrowing { user in
				var response = try User.Details(from: user)
				for match in user.allMatches {
					switch match.status {
					case .active: response.activeMatches.append(try Match.Details(from: match))
					case .ended: response.pastMatches.append(try Match.Details(from: match))
					case .notStarted: continue
					}
				}
				return response
			}
	}

	func list(req: Request) throws -> EventLoopFuture<[User.Details]> {
		let filter = try? req.query.get(at: Query.filter.rawValue) ?? ""
		return User.query(on: req.db)
			.with(\.$hostedMatches)
			.with(\.$joinedMatches)
			.filter(\.$displayName ~~ (filter ?? ""))
			.limit(25) // TODO: Remove limiting for user search, add pagination
			.all()
			.flatMapThrowing { users in
				var response: [User.Details] = []
				for user in users {
					guard var userResponse = try? User.Details(from: user) else { continue }
					for match in user.allMatches {
						switch match.status {
						case .active: userResponse.activeMatches.append(try Match.Details(from: match))
						case .ended: userResponse.pastMatches.append(try Match.Details(from: match))
						case .notStarted: continue
						}
					}
					response.append(userResponse)
				}
				return response
			}
	}

	// MARK: - Authentication

	func createGuest(req: Request) throws -> EventLoopFuture<User.Create.Response> {
		do {
			let hash = try Bcrypt.hash(UUID().uuidString)
			let user = User(
				email: "guest-\(UUID().uuidString)@example.com",
				password: hash,
				displayName: "Guest #\(User.generateRandomGuestName())"
			)

			return user.save(on: req.db)
				.flatMap {
					do {
						let token = try Token.generateToken(forUser: user.requireID(), source: .signup)
						return  token.save(on: req.db)
							.map { token }
					} catch {
						return req.eventLoop.makeFailedFuture(error)
					}
				}
				.flatMapThrowing {
					try User.Create.Response(from: user, withToken: $0)
				}
		} catch  {
			return req.eventLoop.makeFailedFuture(error)
		}
	}

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

	func logout(req: Request) throws -> EventLoopFuture<User.Logout.Response> {
		guard let token = req.headers.bearerAuthorization?.token else {
			throw Abort(.badRequest, reason: "Token must be supplied to logout")
		}

		return Token.query(on: req.db)
			.filter(\.$value == token)
			.delete()
			.transform(to: User.Logout.Response(success: true))
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
		users.post("guestSignup", use: createGuest)
		users.get("all", use: list)
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

		let adminProtected = users.grouped(AdminMiddleware())
		adminProtected.get(use: index)
	}
}
