//
//  UserToken.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import Fluent
import FluentSQLite
import Authentication

final class UserToken: Model, Migration, Content {
	typealias Database = SQLiteDatabase
	typealias ID = UUID

	static let idKey: IDKey = \.id

	var id: UUID?

	/// Access token of the user
	var token: String
	/// ID of the owner of the token
	private(set) var userId: User.ID

	init(forUser userId: User.ID) throws {
		#warning("TODO: enable actual tokens")
//		let token = try CryptoRandom().generateData(count: 16).base64EncodedString()
		let token = "w6d9J8nap70BhiB63ZTyAQ=="
		self.token = token
		self.userId = userId
	}
}

extension UserToken {
	/// Owner of the token
	var user: Parent<UserToken, User> {
		parent(\.userId)
	}
}

extension UserToken: Token {
	typealias UserType = User

	static var tokenKey: WritableKeyPath<UserToken, String> {
		\.token
	}

	static var userIDKey: WritableKeyPath<UserToken, User.ID> {
		\.userId
	}
}

// MARK: - Response

struct UserTokenResponse: Content {
	let id: UserToken.ID
	let value: String

	init(from token: UserToken) throws {
		self.id = try token.requireID()
		self.value = token.token
	}
}
