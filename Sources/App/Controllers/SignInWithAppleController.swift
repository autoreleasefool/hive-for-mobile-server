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
		req.logger.debug("Handling Sign In With Apple request")
		let body = try req.content.decode(User.SignInWithApple.Request.self)

		return req.jwt.apple.verify(
			body.appleIdentityToken,
			applicationIdentifier: ProjectConfig.SignInWithApple.applicationIdentifier
		).flatMap { appleIdentityToken in
			User.findBy(appleIdentifier: appleIdentityToken.subject.value, req: req)
				.flatMap { user in
					if let user = user {
						req.logger.debug("Logging in user \(String(describing: user.id))")
						return self.login(
							appleIdentityToken: appleIdentityToken,
							user: user,
							req: req
						)
					} else {
						req.logger.debug("Signing up new user")
						return self.signUp(
							appleIdentityToken: appleIdentityToken,
							displayName: nil,
							avatarUrl: nil,
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
			displayName: displayName ?? User.anonymousDisplayName,
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
		let siwaUsers = routes.grouped("api", "siwa")
		siwaUsers.post("auth", use: authHandler)
	}
}
