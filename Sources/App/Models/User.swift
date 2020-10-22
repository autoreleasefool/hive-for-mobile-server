//
//  User.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor

final class User: Model, Content {
	static let schema = "users"

	@ID(key: .id)
	var id: UUID?

	/// Unique ID of the user
	@Field(key: "email")
	var email: String

	/// Hashed password
	@Field(key: "password")
	var password: String

	/// Display name of the user
	@Field(key: "display_name")
	var displayName: String

	/// Calculated ELO of the user
	@Field(key: "elo")
	var elo: Int

	/// Link to the user's avatar
	@OptionalField(key: "avatar_url")
	var avatarUrl: String?

	/// `true` if the user has admin priveleges
	@Field(key: "is_admin")
	var isAdmin: Bool

	@Children(for: \.$host)
	var hostedMatches: [Match]

	@Children(for: \.$opponent)
	var joinedMatches: [Match]

	init() { }

	init(email: String, password: String, displayName: String) {
		self.email = email
		self.password = password
		self.displayName = displayName
		self.elo = Elo.Rating.default
		self.isAdmin = false
	}

	init(
		id: User.IDValue? = nil,
		email: String,
		password: String,
		displayName: String,
		elo: Int,
		avatarUrl: String?,
		isAdmin: Bool
	) {
		self.id = id
		self.email = email
		self.password = password
		self.displayName = displayName
		self.elo = elo
		self.avatarUrl = avatarUrl
		self.isAdmin = isAdmin
	}

	var allMatches: [Match] {
		(hostedMatches + joinedMatches).sorted {
			switch ($0.createdAt, $1.createdAt) {
			case (.none, _): return false
			case (.some, .none): return true
			case (.some(let left), .some(let right)): return left < right
			}
		}
	}
}

// MARK: - Aliases

extension Match {
	final class Host: ModelAlias {
		static let name = "user_host"
		let model = User()
	}

	final class Opponent: ModelAlias {
		static let name = "user_opponent"
		let model = User()
	}

	final class Winner: ModelAlias {
		static let name = "user_winner"
		let model = User()
	}
}

// MARK: - Guests

extension User {
	static func generateRandomGuestName() -> String {
		let id = String(Int.random(in: 1...99999))
		return String(repeating: "0" as Character, count: 5 - id.count) + id
	}
}

// MARK: - Modifiers

extension User {
	func recordWin(againstPlayerRated opponentElo: Int, on req: Request) -> EventLoopFuture<User> {
		elo = Elo.Rating(playerRating: elo, opponentRating: opponentElo, outcome: .win).updated
		return self.update(on: req.db)
			.map { self }
	}

	func recordLoss(againstPlayerRated opponentElo: Int, on req: Request) -> EventLoopFuture<User> {
		elo = Elo.Rating(playerRating: elo, opponentRating: opponentElo, outcome: .loss).updated
		return self.update(on: req.db)
			.map { self }
	}

	func recordDraw(againstPlayerRated opponentElo: Int, on req: Request) -> EventLoopFuture<User> {
		elo = Elo.Rating(playerRating: elo, opponentRating: opponentElo, outcome: .draw).updated
		return self.update(on: req.db)
			.map { self }
	}
}

// MARK: - Authentication

extension User: ModelAuthenticatable {
	static let usernameKey = \User.$email
	static let passwordHashKey = \User.$password

	func verify(password: String) throws -> Bool {
		try Bcrypt.verify(password, created: self.password)
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
		validations.add("displayName", as: String.self, is: !.empty && .alphanumeric && .count(3...24))
		validations.add("email", as: String.self, is: .email)
		validations.add("avatarUrl", as: String?.self, is: .nil || .url, required: false)
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

// MARK: - Summary

extension User {
	struct Summary: Content {
		let id: User.IDValue
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

		init(from host: Match.Host) throws {
			try self.init(from: host.model)
		}

		init(from opponent: Match.Opponent) throws {
			try self.init(from: opponent.model)
		}

		init(from winner: Match.Winner) throws {
			try self.init(from: winner.model)
		}
	}
}

// MARK: - Details

extension User {
	struct Details: Content {
		let id: User.IDValue
		let displayName: String
		let elo: Int
		let avatarUrl: String?
		var activeMatches: [Match.Details] = []
		var pastMatches: [Match.Details] = []

		init(from user: User) throws {
			self.id = try user.requireID()
			self.displayName = user.displayName
			self.elo = user.elo
			self.avatarUrl = user.avatarUrl
		}
	}
}
