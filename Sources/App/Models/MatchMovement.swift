//
//  MatchMovement.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor
import HiveEngine

final class MatchMovement: Model, Content {
	static let schema = "match_movements"

	@ID(key: .id)
	var id: UUID?

	/// ID of the match the move was made in
	@Parent(key: "match_id")
	var match: Match

	/// ID of the user that made the move
	@Parent(key: "user_id")
	var user: User

	/// Date and time that the move was made
	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	/// Notation describing the movement made
	@Field(key: "notation")
	var notation: String

	/// Movement number in the game
	@Field(key: "ordinal")
	var ordinal: Int

	init() {}

	init(from: RelativeMovement, userId: User.IDValue, matchId: Match.IDValue, ordinal: Int) {
		self.$user.id = userId
		self.$match.id = matchId
		self.notation = from.notation
		self.ordinal = ordinal
	}
}

// MARK: - Summary

extension MatchMovement {
	struct Summary: Content {
		let id: MatchMovement.IDValue
		let notation: String
		let ordinal: Int
		let date: Date

		init(from movement: MatchMovement) throws {
			self.id = try movement.requireID()
			self.date = movement.createdAt!
			self.notation = movement.notation
			self.ordinal = movement.ordinal
		}
	}
}
