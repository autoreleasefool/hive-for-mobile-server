import Vapor
import FluentSQLite
import Crypto

final class UserController {
	func users(_ request: Request) throws -> Future<[UserResponse]> {
		User.query(on: request)
			.all()
			.map { try $0.map { try UserResponse(from: $0) } }
	}

	func summary(_ request: Request) throws -> Future<UserResponse> {
		try request.parameters.next(User.self)
			.map { try UserResponse(from: $0) }
	}

	func details(_ request: Request) throws -> Future<UserResponse> {
		try request.parameters.next(User.self)
			.flatMap { user in
				let activeMatchesFuture = try user.matches
					.query(on: request)
					.filter(\.status == .active)
					.all()

				let pastMatchesFuture = try user.matches
					.query(on: request)
					.filter(\.status == .ended)
					.all()

				return activeMatchesFuture.and(pastMatchesFuture).map {
					var response = try UserResponse(from: user)
					response.activeMatches = $0
					response.pastMatches = $1
					return response
				}
			}
	}

	func create(_ request: Request) throws -> Future<UserResponse> {
		try request.content.decode(CreateUserRequest.self)
			.flatMap { user -> Future<User> in
				User.query(on: request)
					.filter(\.email == user.email)
					.first()
					.flatMap { existingUser in
						guard user.password == user.verifyPassword else {
							throw Abort(.badRequest, reason: "Password and verification must match.")
						}

						let hash = try BCrypt.hash(user.password)
						return User(email: user.email, password: hash, displayName: user.displayName)
							.save(on: request)
					}
			}.map { try UserResponse(from: $0) }
	}

	func login(_ request: Request) throws -> Future<UserToken> {
		let user = try request.requireAuthenticated(User.self)
		let token = try UserToken(forUser: user.requireID())
		return token.save(on: request)
	}

	func logout(_ request: Request) throws -> Future<HTTPResponseStatus> {
		let user = try request.requireAuthenticated(User.self)
		guard let token = request.http.headers.bearerAuthorization?.token else {
			throw Abort(.badRequest, reason: "Token must be supplied to logout")
		}

		return try user.sessions
			.query(on: request)
			.filter(\.token == token)
			.delete()
			.transform(to: .ok)
	}
}

// MARK: RouteCollection

extension UserController: RouteCollection {
	func boot(router: Router) throws {
		let userGroup = router.grouped("users")

		// Public routes
		userGroup.get(User.parameter, "details", use: details)
		userGroup.get(User.parameter, "summary", use: summary)
		userGroup.post("signup", use: create)

		// Password authenticated routes
		let passwordUserGroup = userGroup.grouped(User.basicAuthMiddleware(using: BCryptDigest()))
		passwordUserGroup.post("login", use: login)

		// Token authenticated routes
		let tokenUserGroup = userGroup.grouped(User.tokenAuthMiddleware())
		tokenUserGroup.delete("logout", use: logout)

		// Admin authenticated routes
		#warning("TODO: enable admin user group for production")
//		let adminUserGroup = router.grouped(AdminMiddleware())
		let adminUserGroup = userGroup
		adminUserGroup.get("all", use: users)
	}
}
