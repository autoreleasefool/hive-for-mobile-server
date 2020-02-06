import Vapor
import FluentSQLite

final class Room: SQLiteUUIDModel, Content, Migration {
	var id: UUID?

	private(set) var host: UUID
	private(set) var opponent: UUID?

	private(set) var options: [String: String]
}
