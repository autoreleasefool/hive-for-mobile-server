//
//  UserController.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import Fluent
import FluentSQLite
import Crypto

final class UserController {
	func users(_ request: Request) throws -> Future<[UserSummaryResponse]> {
		User.query(on: request)
			.sort(\.displayName)
			.all()
			.map { try $0.map { try UserSummaryResponse(from: $0) } }
	}

	func summary(_ request: Request) throws -> Future<UserSummaryResponse> {
		try request.parameters.next(User.self)
			.map { try UserSummaryResponse(from: $0) }
	}

	func details(_ request: Request) throws -> Future<UserDetailsResponse> {
		try request.parameters.next(User.self)
			.flatMap {
				Match.query(on: request)
					.filter(\.status ~~ [.active, .ended])
					.sort(\.createdAt)
					.all()
					.and(result: $0)
			}.map { matches, user in
				#warning("TODO: need to add users/winners to MatchDetailsResponse")
				var response = try UserDetailsResponse(from: user)
				for match in matches {
					guard match.hostId == user.id || match.opponentId == user.id else { continue }
					if match.status == .active {
						response.activeMatches.append(try MatchDetailsResponse(from: match))
					} else if match.status == .ended {
						response.pastMatches.append(try MatchDetailsResponse(from: match))
					}
				}
				return response
			}
	}

	func create(_ request: Request) throws -> Future<CreateUserResponse> {
		try request.content.decode(CreateUserRequest.self)
			.flatMap {
				User.query(on: request)
					.filter(\.email == $0.email)
					.first()
					.and(result: $0)
			}.flatMap { existingUser, user -> Future<User> in
				guard existingUser == nil else {
					throw Abort(.badRequest, reason: "User with email already exists.")
				}

				guard user.password == user.verifyPassword else {
					throw Abort(.badRequest, reason: "Password and verification must match.")
				}

				let hash = try BCrypt.hash(user.password)
				return User(email: user.email.lowercased(), password: hash, displayName: user.displayName)
					.save(on: request)
			}.flatMap {
				try UserToken(forUser: $0.requireID())
					.save(on: request)
					.and(result: $0)
			}.map { token, user in
				return try CreateUserResponse(from: user, withToken: UserTokenResponse(from: token))
			}
	}

	func login(_ request: Request) throws -> Future<UserToken> {
		let user = try request.requireAuthenticated(User.self)
		let token = try UserToken(forUser: user.requireID())
		return token.save(on: request)
	}

	func logout(_ request: Request) throws -> Future<HTTPResponseStatus> {
		let user = try request.requireAuthenticated(User.self)
		guard let token = request.http.headers.bearerAuthorization?.token else {
			throw Abort(.badRequest, reason: "Token must be supplied to logout")
		}

		return try user.sessions
			.query(on: request)
			.filter(\.token == token)
			.delete()
			.transform(to: .ok)
	}

	func validate(_ request: Request) throws -> Future<UserTokenValidationResponse> {
		let user = try request.requireAuthenticated(User.self)
		guard let token = request.http.headers.bearerAuthorization?.token else {
			throw Abort(.badRequest, reason: "Token not supplied for validation")
		}
		let validation = try UserTokenValidationResponse(userId: user.requireID(), token: token)
		return request.future(validation)
	}
}

// MARK: RouteCollection

extension UserController: RouteCollection {
	func boot(router: Router) throws {
		let userGroup = router.grouped("users")

		// Public routes
		userGroup.get(User.parameter, "details", use: details)
		userGroup.get(User.parameter, "summary", use: summary)
		userGroup.post("signup", use: create)

		// Password authenticated routes
		let passwordUserGroup = userGroup.grouped(User.basicAuthMiddleware(using: BCryptDigest()))
		passwordUserGroup.post("login", use: login)

		// Token authenticated routes
		let tokenUserGroup = userGroup.grouped(User.tokenAuthMiddleware())
		tokenUserGroup.delete("logout", use: logout)
		tokenUserGroup.get("validate", use: validate)

		// Admin authenticated routes
		#warning("TODO: enable admin user group for production")
//		let adminUserGroup = router.grouped(AdminMiddleware())
		let adminUserGroup = userGroup
		adminUserGroup.get("all", use: users)
	}
}
