//
//  User.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import FluentSQLite
import Authentication

final class User: SQLiteUUIDModel, Content, Migration, Parameter {
	var id: UUID?

	/// Unique email of the user
	private(set) var email: String
	/// Hashed password
	private(set) var password: String
	/// Display name of the user
	private(set) var displayName: String

	/// Calculated ELO of the user
	private(set) var elo: Int
	/// Link to the user's avatar
	private(set) var avatarUrl: String?
	/// `true` if the user is a bot player
	private(set) var isBot: Bool

	/// `true` if the user has admin priveleges
	private(set) var isAdmin: Bool = false

	init(email: String, password: String, displayName: String) {
		self.email = email
		self.password = password
		self.displayName = displayName
		self.elo = Elo.defaultValue
		self.isBot = false
	}

	init(
		id: UUID?,
		email: String,
		password: String,
		displayName: String,
		elo: Int,
		avatarUrl: String?,
		isBot: Bool,
		isAdmin: Bool
	) {
		self.id = id
		self.email = email
		self.password = password
		self.displayName = displayName
		self.elo = elo
		self.avatarUrl = avatarUrl
		self.isBot = isBot
		self.isAdmin = isAdmin
	}
}

extension User: Validatable {
	static func validations() throws -> Validations<User> {
		var validations = Validations(User.self)
		try validations.add(\.email, .email)
		try validations.add(\.displayName, .alphanumeric && .count(3...24))
		try validations.add(\.avatarUrl, .url || .nil)
		return validations
	}
}

// MARK: - Authentication

extension User: PasswordAuthenticatable {
	static var usernameKey: WritableKeyPath<User, String> {
		\.email
	}

	static var passwordKey: WritableKeyPath<User, String> {
		\.password
	}
}

extension User: TokenAuthenticatable {
	typealias TokenType = UserToken

	var sessions: Children<User, UserToken> {
		children(\.userId)
	}
}

// MARK: - Create

struct CreateUserRequest: Content {
	let email: String
	let password: String
	let verifyPassword: String
	let displayName: String
}

// MARK: - Response

struct CreateUserResponse: Content {
	let id: User.ID
	let email: String
	let displayName: String
	let avatarUrl: String?
	let token: UserTokenResponse

	init(from user: User, withToken token: UserTokenResponse) throws {
		self.id = try user.requireID()
		self.email = user.email
		self.displayName = user.displayName
		self.avatarUrl = user.avatarUrl
		self.token = token
	}
}

struct UserSummaryResponse: Content {
	let id: User.ID
	let displayName: String
	let elo: Int
	let avatarUrl: String?

	init(from user: User) throws {
		self.id = try user.requireID()
		self.displayName = user.displayName
		self.elo = user.elo
		self.avatarUrl = user.avatarUrl
	}

	init?(from user: User?) throws {
		guard let user = user else { return nil }
		try self.init(from: user)
	}
}

struct UserDetailsResponse: Content {
	let id: User.ID
	let displayName: String
	let elo: Int
	let avatarUrl: String?
	var activeMatches: [MatchDetailsResponse] = []
	var pastMatches: [MatchDetailsResponse] = []

	init(from user: User) throws {
		self.id = try user.requireID()
		self.displayName = user.displayName
		self.elo = user.elo
		self.avatarUrl = user.avatarUrl
	}
}

// MARK: - Optional Decode

extension User {
	struct OptionalFields: Decodable {
		let id: UUID?
		let email: String?
		let password: String?
		let displayName: String?
		let elo: Int?
		let avatarUrl: String?
		let isBot: Bool?
		let isAdmin: Bool?
	}

	convenience init?(_ optionalFields: OptionalFields) {
		guard let email = optionalFields.email,
			let password = optionalFields.password,
			let displayName = optionalFields.displayName,
			let elo = optionalFields.elo,
			let isBot = optionalFields.isBot,
			let isAdmin = optionalFields.isAdmin else {
			return nil
		}

		self.init(
			id: optionalFields.id,
			email: email,
			password: password,
			displayName: displayName,
			elo: elo,
			avatarUrl: optionalFields.avatarUrl,
			isBot: isBot,
			isAdmin: isAdmin
		)
	}
}
