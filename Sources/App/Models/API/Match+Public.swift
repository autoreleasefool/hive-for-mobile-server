//
//  Match+Public.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

extension Match {
	enum Public {}
}

extension Match {
	func asPublicDetails(
		withHost host: User? = nil,
		withOpponent opponent: User? = nil
	) throws -> Match.Public.Details {
		try Match.Public.Details(from: self, withHost: host, withOpponent: opponent)
	}
}

extension Match.Public {
	struct Details: Content {
		let id: Match.IDValue
		let options: String
		let gameOptions: String
		let createdAt: Date?
		let duration: TimeInterval?
		let status: Match.Status
		let isComplete: Bool

		var host: User.Public.Summary?
		var opponent: User.Public.Summary?
		var winner: User.Public.Summary?
		var moves: [MatchMovement.Public.Summary] = []

		init(from match: Match, withHost host: User? = nil, withOpponent opponent: User? = nil) throws {
			self.id = try match.requireID()
			self.options = match.options
			self.gameOptions = match.gameOptions
			self.createdAt = match.createdAt
			self.duration = match.duration
			self.status = match.status
			self.isComplete = match.duration != nil
			self.host = try host?.asPublicSummary()
			self.opponent = try opponent?.asPublicSummary()

			if match.$winner.id == match.$host.id {
				self.winner = self.host
			} else if match.$winner.id == match.$opponent.id {
				self.winner = self.opponent
			}
		}
	}
}
