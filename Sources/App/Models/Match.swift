import Vapor
import FluentSQLite
import HiveEngine

enum MatchStatus: Int, Codable {
	/// A match that is waiting for an opponent to join
	case open = 0
	/// A match that has an opponent but has not started
	case notStarted = 1
	/// A match in progress
	case active = 2
	/// A match that has ended
	case ended = 3
}

final class Match: SQLiteUUIDModel, Content, Migration, Parameter {
	var id: UUID?

	/// ID of the user that created the match
	private(set) var hostId: User.ID
	/// ID of the user the match is played against
	private(set) var opponentId: User.ID?

	/// ELO of the host at the start of the game
	private(set) var hostElo: Double
	/// ELO of the opponent at the start of the game
	private(set) var opponentElo: Double?

	/// `true` if the host is White, `false` if the host is Black
	private(set) var hostIsWhite: Bool
	/// Winner of the game. White, Black, or nil for a tie
	private(set) var winner: String?

	/// Options that were used in the game
	private(set) var options: String
	/// History of moves played in the game
	private(set) var moves: [String]

	/// Date that the game was started at
	private(set) var createdAt: Date?
	/// Total duration of the game
	private(set) var duration: TimeInterval?

	/// Status of the game, if it has begun or ended
	private(set) var rawStatus: Int
	/// `true` if the game is being played asynchronously turn based.
	private(set) var isAsyncPlay: Bool

	static var createdAtKey: TimestampKey? {
		\.createdAt
	}

	var status: MatchStatus {
		get {
			return MatchStatus(rawValue: rawStatus)!
		}
		set {
			self.rawStatus = newValue.rawValue
		}
	}

	init(withHost host: User) throws {
		self.hostId = try host.requireID()
		self.hostElo = host.elo
		self.hostIsWhite = true
		self.moves = []
		self.rawStatus = MatchStatus.notStarted.rawValue
		self.isAsyncPlay = false

		let newState = GameState()
		self.options = GameState.Option.encode(newState.options)
	}

	func addOpponent(_ opponent: User.ID, on conn: DatabaseConnectable) -> Future<Match> {
		self.opponentId = opponent
		return self.save(on: conn)
	}
}

// MARK: - Response

struct MatchResponse: Content {
	let id: Match.ID
	let hostElo: Double
	let opponentElo: Double?
	let hostIsWhite: Bool
	let winner: String?
	let options: String
	let moves: [String]
	let createdAt: Date?
	let duration: TimeInterval?
	let status: MatchStatus
	let isAsyncPlay: Bool

	var host: UserResponse?
	var opponent: UserResponse?

	init(from match: Match) throws {
		self.id = try match.requireID()
		self.hostElo = match.hostElo
		self.opponentElo = match.opponentElo
		self.hostIsWhite = match.hostIsWhite
		self.winner = match.winner
		self.options = match.options
		self.moves = match.moves
		self.createdAt = match.createdAt
		self.duration = match.duration
		self.status = match.status
		self.isAsyncPlay = match.isAsyncPlay
	}
}
