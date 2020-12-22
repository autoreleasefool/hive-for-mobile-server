//
//  MatchMovement+Public.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

extension MatchMovement {
	enum Public {}
}

extension MatchMovement {
	func asPublicSummary() throws -> MatchMovement.Public.Summary {
		try MatchMovement.Public.Summary(from: self)
	}
}

extension MatchMovement.Public {
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
