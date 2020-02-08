import Authentication
import FluentSQLite
import Vapor

/// Called before your application initializes.
public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {
	// Register providers first
	try services.register(FluentSQLiteProvider())
	try services.register(AuthenticationProvider())

	// Register routes to the router
	let router = EngineRouter.default()
	try routes(router)
	services.register(router, as: Router.self)

	// Register middleware
	var middlewares = MiddlewareConfig() // Create _empty_ middleware config
	middlewares.use(ErrorMiddleware.self) // Catches errors and converts to HTTP response
	services.register(middlewares)

	// Configure a SQLite database
	let sqlite = try SQLiteDatabase(storage: .memory)

	// Register the configured SQLite database to the database config.
	var databases = DatabasesConfig()
	databases.enableLogging(on: .sqlite)
	databases.add(database: sqlite, as: .sqlite)
	services.register(databases)

	// Configure migrations
	var migrations = MigrationConfig()

	#warning("Workarounds for Xcode 11.4 Beta")
	// Preferred: migrations.add(model: User.self, database: .sqlite)

	User.defaultDatabase = .sqlite
	migrations.add(model: User.self, database: User.defaultDatabase!)

	Match.defaultDatabase = .sqlite
	migrations.add(model: Match.self, database: Match.defaultDatabase!)

	PushToken.defaultDatabase = .sqlite
	migrations.add(model: PushToken.self, database: PushToken.defaultDatabase!)

	UserToken.defaultDatabase = .sqlite
	migrations.add(model: UserToken.self, database: UserToken.defaultDatabase!)

	MatchUser.defaultDatabase = .sqlite
	migrations.add(model: MatchUser.self, database: MatchUser.defaultDatabase!)

//	MatchUser.defaultDatabase = .sqlite
//	migrations.add(model: MatchUser.self, database: MatchUser.defaultDatabase!)

	services.register(migrations)
}
