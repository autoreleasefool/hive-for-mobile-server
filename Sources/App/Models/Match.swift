import Vapor
import FluentSQLite

final class Match: SQLiteUUIDModel, Content, Migration {
	var id: UUID?

	private(set) var host: UUID
	private(set) var opponent: UUID

	private(set) var hostElo: Double
	private(set) var opponentElo: Double

	private(set) var firstPlayer: UUID
	private(set) var winner: UUID?

	private(set) var options: [String: String]
	private(set) var moves: [String]

	private(set) var duration: TimeInterval
}
