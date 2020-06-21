//
//  CreateMatch.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-06-16.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent

struct CreateMatch: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.schema(Match.schema)
			.field("id", .uuid, .identifier(auto: true))
			.field("host_id", .uuid, .required, .references(User.schema, "id"))
			.field("opponent_id", .uuid, .references(User.schema, "id"))
			.field("winner_id", .uuid, .references(User.schema, "id"))
			.field("game_options", .string, .required)
			.field("options", .string, .required)
			.field("created_at", .datetime, .required)
			.field("duration", .double)
			.field("status", .int, .required)
			.create()
	}

	func revert(on database: Database) -> EventLoopFuture<Void> {
		database.schema(Match.schema).delete()
	}
}
