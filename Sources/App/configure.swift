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

	app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

	app.migrations.add(CreateUser())
	app.migrations.add(CreateToken())

	try app.autoMigrate().wait()

	try routes(app)

	// Register WebSocket routes to the router
	// let wss = WebSocketContainer.createWebSocket()
	// sockets(wss)
	// services.register(wss, as: WebSocketServer.self)

	// Register middleware
	// var middlewares = MiddlewareConfig() // Create _empty_ middleware config
	// middlewares.use(ErrorMiddleware.self) // Catches errors and converts to HTTP response
	// services.register(middlewares)
}
