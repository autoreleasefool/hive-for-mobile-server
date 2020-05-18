//
//  Match.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import Fluent
import FluentSQLite
import HiveEngine

extension NSNotification.Name {
	enum Match {
		static let DidUpdate = NSNotification.Name("Match.DidUpdate")
	}
}

enum MatchStatus: Int, SQLiteEnumType {
	/// A match that has an opponent but has not started
	case notStarted = 1
	/// A match in progress
	case active = 2
	/// A match that has ended
	case ended = 3

	static func reflectDecoded() throws -> (MatchStatus, MatchStatus) {
		return (.active, .notStarted)
	}
}

final class Match: SQLiteUUIDModel, Content, Migration, Parameter {
	var id: UUID?

	/// ID of the user that created the match
	private(set) var hostId: User.ID
	/// ID of the user the match is played against
	private(set) var opponentId: User.ID?

	/// ID of the winner of the game. `nil` for a tie
	private(set) var winner: User.ID?

	/// GameState options that were used in the game
	private(set) var gameOptions: String
	/// Options used in the game
	private(set) var options: String

	/// Date that the game was started at
	private(set) var createdAt: Date?
	/// Total duration of the game
	private(set) var duration: TimeInterval?

	/// Status of the game, if it has begun or ended
	private(set) var status: MatchStatus

	static var createdAtKey: TimestampKey? {
		\.createdAt
	}

	init(withHost host: User) throws {
		self.hostId = try host.requireID()
		self.status = .notStarted

		self.options = OptionSet.encode(Match.Option.defaultSet)
		self.gameOptions = OptionSet.encode(GameState().options)
	}

	func otherPlayer(from userId: User.ID) -> User.ID? {
		if hostId == userId {
			return opponentId
		} else if opponentId == userId {
			return hostId
		}

		return nil
	}

	var gameOptionSet: Set<GameState.Option> {
		OptionSet.parse(self.gameOptions)
	}

	var optionSet: Set<Match.Option> {
		OptionSet.parse(self.options)
	}

	func didUpdate(on conn: SQLiteConnection) throws -> EventLoopFuture<Match> {
		NotificationCenter.default.post(name: NSNotification.Name.Match.DidUpdate, object: self)
		return conn.future(self)
	}
}

// MARK: Options

extension Match {
	enum Option: String, CaseIterable {
		case hostIsWhite = "HostIsWhite"
		case asyncPlay = "AsyncPlay"

		static var defaultSet: Set<Match.Option> {
			Set([.hostIsWhite])
		}
	}
}

// MARK: - Modifiers

extension Match {
	func addOpponent(_ opponent: User.ID, on conn: DatabaseConnectable) -> Future<Match> {
		self.opponentId = opponent
		return self.update(on: conn)
	}

	func removeOpponent(_ opponent: User.ID, on conn: DatabaseConnectable) -> Future<Match> {
		self.opponentId = nil
		return self.update(on: conn)
	}

	func begin(on conn: DatabaseConnectable) throws -> Future<Match> {
		let matchId = try requireID()

		guard status == .notStarted else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" is not ready to begin (\#(status))"#)
		}

		guard opponentId != nil else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" has no opponent"#)
		}

		self.status = .active
		return self.update(on: conn)
	}

	func end(winner: User.ID?, on conn: DatabaseConnectable) throws -> Future<Match> {
		let matchId = try requireID()

		guard status == .active else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" is not ready to end (\#(status)"#)
		}

		guard let opponentId = opponentId else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" has no opponent"#)
		}

		self.winner = winner
		status = .ended
		duration = createdAt?.distance(to: Date())

		return self.update(on: conn)
			.flatMap { _ in
				User.query(on: conn)
					.filter(\.id ~~ [self.hostId, opponentId])
					.all()
			}
			.flatMap { users in
				guard let host = users.first(where: { $0.id == self.hostId }),
					let opponent = users.first(where: { $0.id == opponentId }) else {
						throw Abort(
							.badRequest,
							reason: "Could not find all users (\(self.hostId), \(opponentId))"
						)
				}

				// Update Elos and ignore any errors
				return self.resolveNewElos(
					host: host,
					opponent: opponent,
					winner: winner,
					on: conn
				).mapIfError { _ in }
			}
			.mapIfError { _ in }
			.map { self }
	}

	func resolveNewElos(
		host: User,
		opponent: User,
		winner: User.ID?,
		on conn: DatabaseConnectable
	) -> Future<Void> {
		guard let hostId = try? host.requireID() else {
			print("Failed to find ID of host to resolve Elos")
			return conn.eventLoop.newSucceededFuture(result: ())
		}

		let hostUpdate: EventLoopFuture<User>
		let opponentUpdate: EventLoopFuture<User>
		if winner == nil {
			hostUpdate = host.recordDraw(againstPlayerRated: opponent.elo, on: conn)
			opponentUpdate = opponent.recordDraw(againstPlayerRated: host.elo, on: conn)
		} else if winner == hostId {
			hostUpdate = host.recordWin(againstPlayerRated: opponent.elo, on: conn)
			opponentUpdate = opponent.recordLoss(againstPlayerRated: host.elo, on: conn)
		} else {
			hostUpdate = host.recordLoss(againstPlayerRated: opponent.elo, on: conn)
			opponentUpdate = opponent.recordWin(againstPlayerRated: host.elo, on: conn)
		}

		return hostUpdate
			.flatMap { _ in opponentUpdate }
			.transform(to: ())
	}

	func updateOptions(
		options: Set<Match.Option>,
		gameOptions: Set<GameState.Option>,
		on conn: DatabaseConnectable
	) -> Future<Match> {
		self.options = OptionSet.encode(options)
		self.gameOptions = OptionSet.encode(gameOptions)
		return self.update(on: conn)
	}
}

// MARK: - Response

typealias CreateMatchResponse = MatchDetailsResponse
typealias JoinMatchResponse = MatchDetailsResponse

struct MatchDetailsResponse: Content {
	let id: Match.ID
	let options: String
	let gameOptions: String
	let createdAt: Date?
	let duration: TimeInterval?
	let status: MatchStatus
	let isComplete: Bool

	var host: UserSummaryResponse?
	var winner: UserSummaryResponse?
	var opponent: UserSummaryResponse?
	var moves: [MatchMovementResponse] = []

	init(from match: Match, withHost host: User? = nil, withOpponent opponent: User? = nil) throws {
		self.id = try match.requireID()
		self.options = match.options
		self.gameOptions = match.gameOptions
		self.createdAt = match.createdAt
		self.duration = match.duration
		self.status = match.status
		self.isComplete = match.duration != nil

		if let host = host {
			self.host = try UserSummaryResponse(from: host)
		}
		if let opponent = opponent {
			self.opponent = try UserSummaryResponse(from: opponent)
		}
	}
}
