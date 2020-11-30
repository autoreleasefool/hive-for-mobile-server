//
//  configure.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import FluentSQLiteDriver
import Vapor

/// Called before your application initializes.
public func configure(_ app: Application) throws {
	// uncomment to serve files from /Public folder
	// app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

	if let portEnv = Environment.get("PORT"), let port = Int(portEnv) {
		app.http.server.configuration.port = port
	}

	app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

	app.migrations.add(CreateUser())
	app.migrations.add(CreateToken())
	app.migrations.add(CreateMatch())
	app.migrations.add(CreateMatchMovement())
	app.migrations.add(PopulateWithUsers())
	try app.autoMigrate().wait()

	app.middleware.use(SupportedAppVersionMiddleware())
	app.middleware.use(SupportedEngineVersionMiddleware())

	app.gameService = GameManager()
	app.lifecycle.use(BootService())

	try routes(app)
	socketRoutes(app)
}
