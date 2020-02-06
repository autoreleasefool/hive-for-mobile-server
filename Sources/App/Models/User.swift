import Vapor
import FluentSQLite

final class User: SQLiteUUIDModel, Content, Migration {
	var id: UUID?

	private(set) var email: String
	private(set) var password: String
	private(set) var displayName: String

	private(set) var elo: Double?
	private(set) var avatarUrl: String?
	private(set) var isBot: Bool
}
