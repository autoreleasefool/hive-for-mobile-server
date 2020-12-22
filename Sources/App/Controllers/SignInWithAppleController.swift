//
//  SignInWithAppleController.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-21.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import JWT
import Vapor

final class SignInWithAppleController {
	func authHandler(req: Request) throws -> EventLoopFuture<User.Authentication.Response> {
		let body = try req.content.decode(User.SignInWithApple.Request.self)

		return req.jwt.apple.verify(
			body.appleIdentityToken,
			applicationIdentifier: ProjectConfig.SignInWithApple.applicationIdentifier
		).flatMap { appleIdentityToken in
			User.findBy(appleIdentifier: appleIdentityToken.subject.value, req: req)
				.flatMap { user in
					if let user = user {
						return self.login(
							appleIdentityToken: appleIdentityToken,
							user: user,
							req: req
						)
					} else {
						return self.signUp(
							appleIdentityToken: appleIdentityToken,
							displayName: body.displayName,
							avatarUrl: body.avatarUrl,
							req: req
						)
					}
				}
		}
	}

	private func signUp(
		appleIdentityToken: AppleIdentityToken,
		displayName: String?,
		avatarUrl: String?,
		req: Request
	) -> EventLoopFuture<User.Authentication.Response> {
		let user = User(
			appleUserIdentifier: appleIdentityToken.subject.value,
			displayName: displayName ?? "Anonymous",
			avatarUrl: avatarUrl,
			isGuest: false
		)

		return user.save(on: req.db)
			.flatMap {
				guard let token = try? user.generateToken(source: .signup),
							let userSummary = try? user.asPublicSummary() else {
					return req.eventLoop.makeFailedFuture(Abort(.internalServerError))
				}
				return token.save(on: req.db)
					.map { User.Authentication.Response(accessToken: token.value, user: userSummary) }
			}
	}

	private func login(
		appleIdentityToken: AppleIdentityToken,
		user: User,
		req: Request
	) -> EventLoopFuture<User.Authentication.Response> {
		guard let token = try? user.generateToken(source: .login),
					let userSummary = try? user.asPublicSummary() else {
			return req.eventLoop.makeFailedFuture(Abort(.internalServerError))
		}
		return token.save(on: req.db)
			.map { User.Authentication.Response(accessToken: token.value, user: userSummary) }
	}
}

// MARK: - RouteCollection

extension SignInWithAppleController: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		let siwaUsers = routes.grouped("api", "users", "siwa")
		siwaUsers.post(use: authHandler)
	}
}
