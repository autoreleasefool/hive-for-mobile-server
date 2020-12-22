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

	// Unique identifier from Sign in with Apple
	@Field(key: "apple_identifier")
	var appleUserIdentifier: String

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

	/// `true` if the user is a guest account
	@Field(key: "is_guest")
	var isGuest: Bool

	@Children(for: \.$host)
	var hostedMatches: [Match]

	@Children(for: \.$opponent)
	var joinedMatches: [Match]

	init() {}

	init(appleUserIdentifier: String, displayName: String, avatarUrl: String?, isGuest: Bool) {
		self.appleUserIdentifier = appleUserIdentifier
		self.displayName = displayName
		self.elo = Elo.Rating.default
		self.isAdmin = false
		self.isGuest = isGuest
	}

	init(
		id: User.IDValue? = nil,
		appleUserIdentifier: String,
		displayName: String,
		elo: Int,
		avatarUrl: String?,
		isAdmin: Bool,
		isGuest: Bool
	) {
		self.id = id
		self.appleUserIdentifier = appleUserIdentifier
		self.displayName = displayName
		self.elo = elo
		self.avatarUrl = avatarUrl
		self.isAdmin = isAdmin
		self.isGuest = isGuest
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

// MARK: - Filters

extension User {
	static func findBy(appleIdentifier identifier: String, req: Request) -> EventLoopFuture<User?> {
		User.query(on: req.db)
			.filter(\.$appleUserIdentifier == identifier)
			.first()
	}
}
