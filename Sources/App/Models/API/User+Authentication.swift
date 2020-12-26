//
//  User+Authentication.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-21.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

extension User: Authenticatable {}

extension User {
	enum Authentication {}
	enum SignInWithApple {}
}

extension User.Authentication {
	enum Response: Content {
		enum CodingKeys: String, CodingKey {
			// V1 keys
			case userId
			case sessionId
			case token

			// V2 keys
			case accessToken
			case user
		}

		case v1(SessionToken)
		case v2(User.Authentication.SuccessResponse)

		init(accessToken: String, user: User.Public.Summary) {
			self = .v2(User.Authentication.SuccessResponse(accessToken: accessToken, user: user))
		}

		init(userId: User.IDValue, sessionId: Token.IDValue, token: String) {
			self = .v1(SessionToken(userId: userId, sessionId: sessionId, token: token))
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			if container.contains(.sessionId) {
				let sessionId = try container.decode(Token.IDValue.self, forKey: .sessionId)
				let userId = try container.decode(User.IDValue.self, forKey: .userId)
				let token = try container.decode(String.self, forKey: .token)
				self = .v1(SessionToken(userId: userId, sessionId: sessionId, token: token))
			} else {
				let accessToken = try container.decode(String.self, forKey: .accessToken)
				let user = try container.decode(User.Public.Summary.self, forKey: .user)
				self = .v2(User.Authentication.SuccessResponse(accessToken: accessToken, user: user))
			}
		}

		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			switch self {
			case .v1(let sessionToken):
				try container.encode(sessionToken.sessionId, forKey: .sessionId)
				try container.encode(sessionToken.userId, forKey: .userId)
				try container.encode(sessionToken.token, forKey: .token)
			case .v2(let response):
				try container.encode(response.accessToken, forKey: .accessToken)
				try container.encode(response.user, forKey: .user)
			}
		}
	}

	struct SuccessResponse: Content {
		let accessToken: String
		let user: User.Public.Summary
	}
}

// MARK: - Sign in with Apple

extension User.SignInWithApple {
	struct Request: Content {
		let appleIdentityToken: String
	}
}

// MARK: - Create

extension User {
	struct Create: Content {
		let email: String
		let displayName: String
		let password: String
		let verifyPassword: String
		let avatarUrl: String?
	}
}

extension User.Create: Validatable {
	static func validations(_ validations: inout Validations) {
		validations.validateDisplayName()
		validations.validateEmail()
		validations.validateAvatarUrl()
	}
}

extension User.Create {
	enum Response: Content {
		enum CodingKeys: String, CodingKey {
			// V1 keys
			case id
			case email
			case displayName
			case avatarUrl
			case token

			// V2 keys
			case accessToken
			case user
		}

		case v1(User.Create.V1Response)
		case v2(User.Authentication.SuccessResponse)

		init(accessToken: String, user: User.Public.Summary) {
			self = .v2(User.Authentication.SuccessResponse(accessToken: accessToken, user: user))
		}

		init(
			id: User.IDValue,
			email: String,
			displayName: String,
			avatarUrl: String?,
			token: Token
		) throws {
			self = .v1(
				User.Create.V1Response(
					id: id,
					email: email,
					displayName: displayName,
					avatarUrl: avatarUrl,
					token: SessionToken(
						userId: id,
						sessionId: try token.requireID(),
						token: token.value
					)
				)
			)
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			if container.contains(.id) {
				let id = try container.decode(User.IDValue.self, forKey: .id)
				let email = try container.decode(String.self, forKey: .email)
				let displayName = try container.decode(String.self, forKey: .displayName)
				let avatarUrl = try container.decode(String.self, forKey: .avatarUrl)
				let token = try container.decode(SessionToken.self, forKey: .token)
				self = .v1(
					User.Create.V1Response(
						id: id,
						email: email,
						displayName: displayName,
						avatarUrl: avatarUrl,
						token: token
					)
				)
			} else {
				let accessToken = try container.decode(String.self, forKey: .accessToken)
				let user = try container.decode(User.Public.Summary.self, forKey: .user)
				self = .v2(User.Authentication.SuccessResponse(accessToken: accessToken, user: user))
			}
		}

		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			switch self {
			case .v1(let response):
				try container.encode(response.id, forKey: .id)
				try container.encode(response.email, forKey: .email)
				try container.encode(response.displayName, forKey: .displayName)
				try container.encode(response.avatarUrl, forKey: .avatarUrl)
				try container.encode(response.token, forKey: .token)
			case .v2(let response):
				try container.encode(response.accessToken, forKey: .accessToken)
				try container.encode(response.user, forKey: .user)
			}
		}
	}

	struct V1Response: Content {
		let id: User.IDValue
		let email: String
		let displayName: String
		let avatarUrl: String?
		let token: SessionToken

		init(id: User.IDValue, email: String, displayName: String, avatarUrl: String?, token: SessionToken) {
			self.id = id
			self.email = email
			self.displayName = displayName
			self.avatarUrl = avatarUrl
			self.token = token
		}

		init(from user: User, withToken token: Token) throws {
			self.id = try user.requireID()
			self.email = user.email
			self.displayName = user.displayName
			self.avatarUrl = user.avatarUrl
			self.token = try SessionToken(user: user, token: token)
		}
	}
}

// MARK: - Logout

extension User {
	enum Logout {}
}

extension User.Logout {
	struct Response: Content {
		let success: Bool
	}
}

// MARK: - Response

extension User {
	static func buildAuthenticationResponse(
		_ req: Request,
		_ user: User,
		_ token: Token
	) throws -> EventLoopFuture<User.Authentication.Response> {
		guard let appVersion = try req.appVersion() else {
			throw Abort(.imATeapot, reason: "App version `null` is not supported")
		}

		let response: User.Authentication.Response
		if appVersion <= SemVer(majorVersion: 1, minorVersion: 3, patchVersion: 2) {
			response = try .v1(SessionToken(user: user, token: token))
		} else {
			response = try .v2(User.Authentication.SuccessResponse(accessToken: token.value, user: user.asPublicSummary()))
		}

		return req.eventLoop.makeSucceededFuture(response)
	}
}

extension User {
	static func buildCreateResponse(
		_ req: Request,
		_ user: User,
		_ token: Token
	) throws -> EventLoopFuture<User.Create.Response> {
		guard let appVersion = try req.appVersion() else {
			throw Abort(.imATeapot, reason: "App version `null` is not supported")
		}

		let response: User.Create.Response
		if appVersion <= SemVer(majorVersion: 1, minorVersion: 3, patchVersion: 2) {
			response = try .v1(User.Create.V1Response(from: user, withToken: token))
		} else {
			response = try .v2(User.Authentication.SuccessResponse(accessToken: token.value, user: user.asPublicSummary()))
		}

		return req.eventLoop.makeSucceededFuture(response)
	}
}
