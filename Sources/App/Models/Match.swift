import Vapor
import FluentSQLite

final class Match: SQLiteUUIDModel, Content, Migration {
	var id: UUID?

	/// ID of the user that created the match
	private(set) var hostId: UUID

	/// ELO of the host at the start of the game
	private(set) var hostElo: Double?
	/// ELO of the opponent at the start of the game
	private(set) var opponentElo: Double?

	/// `true` if the host is White, `false` if the host is Black
	private(set) var hostPlaysFirst: Bool
	/// Winner of the game. White, Black, or nil for a tie
	private(set) var winner: String?

	/// Options that were used in the game
	private(set) var options: [String: String]
	/// History of moves played in the game
	private(set) var moves: [String]

	/// Date that the game was started at
	private(set) var createdAt: Date?
	/// Total duration of the game
	private(set) var duration: TimeInterval

	/// `true` if the game is actively being played and a winner has not been determined
	private(set) var isActive: Bool
	/// `true` if the game is being played asynchronously turn based.
	private(set) var isAsyncPlay: Bool

	static var createdAtKey: TimestampKey? {
		\.createdAt
	}
}
