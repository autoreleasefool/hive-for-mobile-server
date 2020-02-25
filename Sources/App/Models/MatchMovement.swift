import Vapor
import FluentSQLite
import HiveEngine

final class MatchMovement: SQLiteUUIDModel, Content, Migration {
	var id: UUID?

	/// ID of the match the move was made in
	private(set) var matchId: Match.ID
	/// ID of the user that made the move
	private(set) var userId: User.ID

	/// Date that the move was made
	private(set) var createdAt: Date?

	/// Notation describing the movement made
	private(set) var notation: String
	/// Movement number in the game
	private(set) var ordinal: Int

	static var createdAtKey: TimestampKey? {
		\.createdAt
	}

	init(from: RelativeMovement, withContext context: WSClientMatchContext) {
		self.matchId = context.matchId
		self.userId = context.user
		self.notation = from.notation
		self.ordinal = context.state.move
	}
}

// MARK: - Match Relation

extension MatchMovement {
	/// Match that the move was made in
	var match: Parent<MatchMovement, Match> {
		parent(\.matchId)
	}
}

extension Match {
	/// Moves made in the match
	var moves: Children<Match, MatchMovement> {
		children(\.matchId)
	}
}

// MARK: - User Relation

extension MatchMovement {
	/// User that made the movement
	var user: Parent<MatchMovement, User> {
		parent(\.userId)
	}
}

extension User {
	/// Moves made by the user
	var moves: Children<User, MatchMovement> {
		children(\.userId)
	}
}

// MARK: - Response

struct MatchMovementResponse: Content {
	let id: MatchMovement.ID
	let notation: String
	let ordinal: Int

	init(from movement: MatchMovement) throws {
		self.id = try movement.requireID()
		self.notation = movement.notation
		self.ordinal = movement.ordinal
	}
}
