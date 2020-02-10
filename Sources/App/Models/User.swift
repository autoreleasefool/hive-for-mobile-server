import Vapor
import FluentSQLite
import Authentication

final class User: SQLiteUUIDModel, Content, Migration, Parameter {
	var id: UUID?

	/// Unique email of the user
	private(set) var email: String
	/// Hashed password
	private(set) var password: String
	/// Display name of the user
	private(set) var displayName: String

	/// Calculated ELO of the user
	private(set) var elo: Double
	/// Link to the user's avatar
	private(set) var avatarUrl: String?
	/// `true` if the user is a bot player
	private(set) var isBot: Bool

	/// `true` if the user has admin priveleges
	private(set) var isAdmin: Bool = false

	init(email: String, password: String, displayName: String) {
		self.email = email
		self.password = password
		self.displayName = displayName
		self.elo = Elo.defaultValue
		self.isBot = false
	}
}

extension User: Validatable {
	static func validations() throws -> Validations<User> {
		var validations = Validations(User.self)
		try validations.add(\.email, .email)
		try validations.add(\.displayName, .alphanumeric && .count(3...))
		try validations.add(\.avatarUrl, .url || .nil)
		return validations
	}
}

// MARK: - Authentication

extension User: PasswordAuthenticatable {
	static var usernameKey: WritableKeyPath<User, String> {
		\.email
	}

	static var passwordKey: WritableKeyPath<User, String> {
		\.password
	}
}

extension User {
	var sessions: Children<User, UserToken> {
		children(\.userId)
	}
}

extension User: TokenAuthenticatable {
	typealias TokenType = UserToken
}

// MARK: Request

struct CreateUserRequest: Content {
	let email: String
	let password: String
	let verifyPassword: String
	let displayName: String
}

// MARK: Response

struct UserResponse: Content {
	let id: User.ID
	let displayName: String
	let elo: Double
	let avatarUrl: String?

	var activeMatches: [Match]?
	var pastMatches: [Match]?

	init(from user: User) throws {
		self.id = try user.requireID()
		self.displayName = user.displayName
		self.elo = user.elo
		self.avatarUrl = user.avatarUrl
	}
}
