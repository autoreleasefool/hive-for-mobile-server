import Vapor
import FluentSQLite
import HiveEngine

enum MatchStatus: Int, Codable {
	case notStarted = 0
	case active = 1
	case ended = 2
}

final class Match: SQLiteUUIDModel, Content, Migration, Parameter {
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
	private(set) var options: String
	/// History of moves played in the game
	private(set) var moves: [String]

	/// Date that the game was started at
	private(set) var createdAt: Date?
	/// Total duration of the game
	private(set) var duration: TimeInterval?

	/// Status of the game, if it has begun or ended
	private(set) var status: MatchStatus
	/// `true` if the game is being played asynchronously turn based.
	private(set) var isAsyncPlay: Bool

	static var createdAtKey: TimestampKey? {
		\.createdAt
	}

	init(withHost host: User) throws {
		self.hostId = try host.requireID()
		self.hostPlaysFirst = true
		self.moves = []
		self.status = .notStarted
		self.isAsyncPlay = false

		let newState = GameState()
		self.options = GameState.Option.encode(newState.options)
	}
}

// MARK: - Response

struct MatchResponse: Content {
	let id: Match.ID
	let hostId: User.ID
	let hostElo: Double?
	let opponentElo: Double?
	let hostPlaysFirst: Bool
	let winner: String?
	let options: String
	let moves: [String]
	let createdAt: Date?
	let duration: TimeInterval?
	let status: MatchStatus
	let isAsyncPlay: Bool

	init(from match: Match) throws {
		self.id = try match.requireID()
		self.hostId = match.hostId
		self.hostElo = match.hostElo
		self.opponentElo = match.opponentElo
		self.hostPlaysFirst = match.hostPlaysFirst
		self.winner = match.winner
		self.options = match.options
		self.moves = match.moves
		self.createdAt = match.createdAt
		self.duration = match.duration
		self.status = match.status
		self.isAsyncPlay = match.isAsyncPlay
	}
}
