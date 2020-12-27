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
			.filter(\.$isGuest == false)
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

	// MARK: - Authentication
	func createGuest(req: Request) throws -> EventLoopFuture<User.Create.Response> {
		do {
			let hash = try Bcrypt.hash(UUID().uuidString)
			let user = User(
				email: "guest-\(UUID().uuidString)@example.com",
				password: hash,
				displayName: "Guest #\(User.generateRandomGuestName())",
				avatarUrl: nil,
				isGuest: true
			)

			return user.save(on: req.db)
				.flatMap { _ -> EventLoopFuture<Token> in
					do {
						let token = try user.generateToken(source: .signup)
						return  token.save(on: req.db)
							.map { token }
					} catch {
						return req.eventLoop.makeFailedFuture(error)
					}
				}
				.flatMap {
					do {
						return try User.buildCreateResponse(req, user, $0)
					} catch {
						return req.eventLoop.makeFailedFuture(error)
					}
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
					let user = User(
						email: create.email.lowercased(),
						password: hash,
						displayName: create.displayName,
						avatarUrl: nil,
						isGuest: false
					)
					return user.save(on: req.db)
						.map { user }
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
			.flatMap { user -> EventLoopFuture<(User, Token)> in
				do {
					let token = try user.generateToken(source: .signup)
					return token.save(on: req.db)
						.map { (user, token) }
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
			.flatMap { (user, token) in
				do {
					return try User.buildCreateResponse(req, user, token)
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
			}
	}

	func login(req: Request) throws -> EventLoopFuture<User.Authentication.Response> {
		let user = try req.auth.require(User.self)
		let token = try user.generateToken(source: .login)
		return token.save(on: req.db)
			.flatMap {
				do {
					return try User.buildAuthenticationResponse(req, user, token)
				} catch {
					return req.eventLoop.makeFailedFuture(error)
				}
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
		return try User.buildAuthenticationResponse(req, user, token)
	}

	func update(req: Request) throws -> EventLoopFuture<User.Public.Summary> {
		try User.Public.Update.validate(req)
		let user = try req.auth.require(User.self)
		let update = try req.content.decode(User.Public.Update.self)

		if let displayName = update.displayName {
			user.displayName = displayName
		}

		if let avatarUrl = update.avatarUrl {
			user.avatarUrl = avatarUrl
		}

		// Validations
		if user.displayName == User.anonymousDisplayName
				&& (update.displayName == nil || update.displayName?.isEmpty == true) {
			throw Abort(.badRequest, reason: "Display name cannot be `Anonymous`")
		}
		if user.displayName == User.anonymousDisplayName {
			throw Abort(.badRequest, reason: "Display name cannot be `Anonymous`")
		}

		return user.save(on: req.db)
			.flatMapThrowing { try user.asPublicSummary() }
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
		tokenProtected.post("update", use: update)

		let adminProtected = users.grouped(AdminMiddleware())
		adminProtected.get(use: index)
	}
}
