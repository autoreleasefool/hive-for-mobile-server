//
//  BootService.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-11-29.
//

import Vapor

struct BootService: LifecycleHandler {
	func didBoot(_ app: Application) throws {
		app.eventLoopGroup.next().scheduleRepeatedTask(
			initialDelay: .seconds(0),
			delay: .minutes(5)
		) { _ in
			app.logger.debug("Starting task to clean expired games")
			_ = app.cleanupExpiredGames()
		}
	}
}
