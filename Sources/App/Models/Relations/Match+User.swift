import FluentSQLite

final class MatchUser: SQLiteUUIDPivot, Migration {
	typealias Database = SQLiteDatabase
	typealias Left = Match
	typealias Right = User

	static var leftIDKey: LeftIDKey = \.matchId
	static var rightIDKey: RightIDKey = \.userId

	var id: UUID?

	var matchId: Match.ID
	var userId: User.ID
}

extension Match {
	var players: Siblings<Match, User, MatchUser> {
		siblings()
	}
}

extension User {
	var matches: Siblings<User, Match, MatchUser> {
		siblings()
	}
}
