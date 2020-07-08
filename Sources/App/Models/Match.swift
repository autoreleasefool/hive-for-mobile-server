//
//  Match.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor
import HiveEngine

final class Match: Model, Content {
	static let schema = "matches"

	@ID(key: .id)
	var id: UUID?

	/// User that created the match
	@Parent(key: "host_id")
	var host: User

	/// User the match is played against
	@OptionalParent(key: "opponent_id")
	var opponent: User?

	@OptionalParent(key: "winner_id")
	var winner: User?

	/// HiveEngine options that were used in the game
	@Field(key: "game_options")
	var gameOptions: String

	/// Match options that were used in the game
	@Field(key: "options")
	var options: String

	/// Date that the game was started at
	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	/// Total duration of the game
	@OptionalField(key: "duration")
	var duration: TimeInterval?

	/// Status of the game, if it has begun or ended
	@Field(key: "status")
	var status: Status

	@Children(for: \.$match)
	var moves: [MatchMovement]

	init() {}

	init(withHost host: User) throws {
		self.$host.id = try host.requireID()
		self.status = .notStarted
		self.options = OptionSet.encode(Match.Option.defaultSet)
		self.gameOptions = OptionSet.encode(GameState().options)
	}

	func opponent(for userId: User.IDValue) -> User.IDValue? {
		if userId == self.$host.id {
			return $opponent.id
		} else if userId == self.$opponent.id {
			return $host.id
		}

		return nil
	}

	var gameOptionSet: Set<GameState.Option> {
		OptionSet.parse(gameOptions)
	}

	var optionSet: Set<Option> {
		OptionSet.parse(options)
	}
}

// MARK: - Options

extension Match {
	enum Option: String, CaseIterable {
		case hostIsWhite = "HostIsWhite"
		case asyncPlay = "AsyncPlay"

		static var defaultSet: Set<Self> {
			[.hostIsWhite]
		}
	}
}

// MARK: - Status

extension Match {
	enum Status: Int, Codable {
		case notStarted = 1
		case active = 2
		case ended = 3
	}
}

// MARK: - Modifiers

extension Match {
	func add(opponent: User.IDValue, on req: Request) -> EventLoopFuture<Match> {
		self.$opponent.id = opponent
		return self.update(on: req.db)
			.map { self }
	}

	func remove(opponent: User.IDValue, on req: Request) -> EventLoopFuture<Match> {
		guard self.$opponent.id == opponent else { return req.eventLoop.makeSucceededFuture(self) }
		self.$opponent.id = nil
		return self.update(on: req.db)
			.map { self }
	}

	func begin(on req: Request) throws -> EventLoopFuture<Match> {
		let matchId = try requireID()

		guard status == .notStarted else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" is not ready to begin (\#(status))"#)
		}

		guard $opponent.id != nil else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" has no opponent"#)
		}

		self.status = .active
		return self.update(on: req.db)
			.map { self }
	}

	func end(winner: User.IDValue?, on req: Request) throws -> EventLoopFuture<Match> {
		let matchId = try requireID()

		guard status == .active else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" is not ready to end (\#(status))"#)
		}

		guard $opponent.id != nil else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" has no opponent"#)
		}

		self.$winner.id = winner
		status = .ended
		duration = createdAt?.distance(to: Date())

		return self.update(on: req.db)
			.flatMap { self.$host.load(on: req.db) }
			.flatMap { self.$opponent.load(on: req.db) }
			.flatMap {
				guard let host = self.$host.value,
					let optionalOpponent = self.$opponent.value,
					let opponent = optionalOpponent else {
					return req.eventLoop.makeFailedFuture(Abort(
						.badRequest,
						reason: "Could not find all users (\(self.$host.id), \(String(describing: self.$opponent.id)))"
					))
				}

				// Update ELOs and ignore any errors
				return self.resolveNewElos(
					host: host,
					opponent: opponent,
					winner: self.$winner.id,
					on: req
				)
			}
			.map { self }
	}

	func resolveNewElos(
		host: User,
		opponent: User,
		winner: User.IDValue?,
		on req: Request
	) -> EventLoopFuture<Void> {
		guard let hostId = try? host.requireID() else {
			print("Failed to find ID of host to resolve Elos")
			return req.eventLoop.makeSucceededFuture(())
		}

		let hostUpdate: EventLoopFuture<User>
		let opponentUpdate: EventLoopFuture<User>
		if winner == nil {
			hostUpdate = host.recordDraw(againstPlayerRated: opponent.elo, on: req)
			opponentUpdate = opponent.recordDraw(againstPlayerRated: host.elo, on: req)
		} else if winner == hostId {
			hostUpdate = host.recordWin(againstPlayerRated: opponent.elo, on: req)
			opponentUpdate = opponent.recordLoss(againstPlayerRated: host.elo, on: req)
		} else {
			hostUpdate = host.recordLoss(againstPlayerRated: opponent.elo, on: req)
			opponentUpdate = opponent.recordWin(againstPlayerRated: host.elo, on: req)
		}

		return hostUpdate
			.and(opponentUpdate)
			.transform(to: ())
	}

	func updateOptions(
		options: Set<Match.Option>,
		gameOptions: Set<GameState.Option>,
		on req: Request
	) -> EventLoopFuture<Match> {
		self.options = OptionSet.encode(options)
		self.gameOptions = OptionSet.encode(gameOptions)
		return self.update(on: req.db)
			.map { self }
	}
}

// MARK: - Details

extension Match {
	struct Details: Content {
		let id: Match.IDValue
		let options: String
		let gameOptions: String
		let createdAt: Date?
		let duration: TimeInterval?
		let status: Status
		let isComplete: Bool

		var host: User.Summary?
		var opponent: User.Summary?
		var winner: User.Summary?
		var moves: [MatchMovement.Summary] = []

		init(from match: Match, withHost host: User? = nil, withOpponent opponent: User? = nil) throws {
			self.id = try match.requireID()
			self.options = match.options
			self.gameOptions = match.gameOptions
			self.createdAt = match.createdAt
			self.duration = match.duration
			self.status = match.status
			self.isComplete = match.duration != nil
			self.host = try User.Summary(from: host)
			self.opponent = try User.Summary(from: opponent)

			if match.$winner.id == match.$host.id {
				self.winner = self.host
			} else if match.$winner.id == match.$opponent.id {
				self.winner = self.opponent
			}
		}
	}
}

// MARK: - Create

extension Match {
	struct Create {
		typealias Response = Match.Details
	}
}

// MARK: - Join

extension Match {
	struct Join {
		typealias Response = Match.Details
	}
}

// MARK: - Delete

extension Match {
	struct Delete {
		struct Response: Content {
			let success: Bool
		}
	}
}
