//
//  User+Public.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

extension User {
	enum Public {}
}

// MARK: Summary

extension User {
	func asPublicSummary() throws -> User.Public.Summary {
		try User.Public.Summary(from: self)
	}
}

extension User.Public {
	struct Summary: Content {
		let id: User.IDValue
		let displayName: String
		let elo: Int
		let avatarUrl: String?
		let isGuest: Bool

		init(from user: User) throws {
			self.id = try user.requireID()
			self.displayName = user.displayName
			self.elo = user.elo
			self.avatarUrl = user.avatarUrl
			self.isGuest = user.isGuest
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
	func asPublicDetails() throws -> User.Public.Details {
		try User.Public.Details(from: self)
	}
}

extension User.Public {
	struct Details: Content {
		let id: User.IDValue
		let displayName: String
		let elo: Int
		let avatarUrl: String?
		let isGuest: Bool
		var activeMatches: [Match.Public.Details] = []
		var pastMatches: [Match.Public.Details] = []

		init(from user: User) throws {
			self.id = try user.requireID()
			self.displayName = user.displayName
			self.elo = user.elo
			self.avatarUrl = user.avatarUrl
			self.isGuest = user.isGuest
		}
	}
}

// MARK: - Update

extension User.Public {
	struct Update: Content {
		let displayName: String?
		let avatarUrl: String?
	}
}

extension User.Public.Update: Validatable {
	static func validations(_ validations: inout Validations) {
		validations.validateDisplayName()
		validations.validateAvatarUrl()
	}
}
