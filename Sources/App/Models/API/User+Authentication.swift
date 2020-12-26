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
	struct Response: Content {
		let id: User.IDValue
		let email: String
		let displayName: String
		let avatarUrl: String?
		let token: SessionToken

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
