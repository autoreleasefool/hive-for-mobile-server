//
//  app.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

/// Creates an instance of `Application`. This is called from `main.swift` in the run target.
public func app(_ env: Environment) throws -> Application {
	var config = Config.default()
	var env = env
	var services = Services.default()
	try configure(&config, &env, &services)
	let app = try Application(config: config, environment: env, services: services)
	try boot(app)
	return app
}
