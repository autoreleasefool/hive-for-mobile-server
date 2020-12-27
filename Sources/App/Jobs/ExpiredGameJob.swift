//
//  ExpiredGameJob.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-11-29.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor

struct ExpiredGameJob {
	let id: Match.IDValue

	func invoke(_ app: Application) -> EventLoopFuture<Void> {
		let gameService = app.gameService
		guard !gameService.doesActiveGameExist(withId: id) else {
			return app.eventLoopGroup.next().future()
		}

		return Match.find(id, on: app.db)
			.unwrap(or: Error.matchNotFound)
			.flatMap { match in
				if match.status == .notStarted {
					return match.delete(on: app.db)
				} else {
					return app.eventLoopGroup.next().future()
				}
			}
	}
}

// MARK: Error

extension ExpiredGameJob {
	enum Error: Swift.Error {
		case matchNotFound
	}
}

// MARK: Application

extension Application {
	func cleanupExpiredGames() -> EventLoopFuture<Void> {
		Match.query(on: db)
			.filter(\Match.$status == .notStarted)
			.all()
			.flatMap { [unowned self] matches in
				do {
					return try matches.map {
						let id = try $0.requireID()
						return ExpiredGameJob(id: id).invoke(self)
					}.flatten(on: eventLoopGroup.next())
				} catch {
					return eventLoopGroup.next().future()
				}
			}
	}
}
