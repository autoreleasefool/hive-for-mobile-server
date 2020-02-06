import Vapor
import Fluent
import FluentSQLite

final class PushToken: Model, Content, Migration {
	typealias Database = SQLiteDatabase
	typealias ID = String

	static let idKey: IDKey = \.token

	var token: String?
	private(set) var user: UUID
}
