//
//  Token.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor

enum SessionSource: Int, Content {
	case signup
	case login
}

final class Token: Model {
	static let schema = "tokens"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Field(key: "value")
	var value: String

	@Field(key: "source")
	var source: SessionSource

	@OptionalField(key: "expires_at")
	var expiresAt: Date?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(id: Token.IDValue? = nil, userId: User.IDValue, token: String, source: SessionSource, expiresAt: Date?) {
		self.id = id
		self.$user.id = userId
		self.value = token
		self.source = source
		self.expiresAt = expiresAt
	}

	static func generateToken(forUser userId: User.IDValue, source: SessionSource) throws -> Token {
		// Uncomment for token expiration
//		let calendar = Calendar(identifier: .gregorian)
//		let expiryDate = calendar.date(byAdding: .year, value: 1, to: Date())

		Token(
			userId: userId,
			token: [UInt8].random(count: 32).base64,
			source: source,
			expiresAt: nil
		)
	}
}

extension User {
	func generateToken(source: SessionSource) throws -> Token {
		try Token.generateToken(forUser: self.requireID(), source: source)
	}
}

// MARK: - Authentication

extension Token: ModelTokenAuthenticatable {
	static let valueKey = \Token.$value
	static let userKey = \Token.$user

	var isValid: Bool {
		guard let expiryDate = expiresAt else {
			return true
		}

		return expiryDate > Date()
	}
}
