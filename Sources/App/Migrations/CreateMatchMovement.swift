//
//  CreateMatchMovement.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-06-16.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent

struct CreateMatchMovement: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.schema(MatchMovement.schema)
			.field("id", .uuid, .identifier(auto: true))
			.field("match_id", .uuid, .required, .references(Match.schema, "id"))
			.field("user_id", .uuid, .references(User.schema, "id"))
			.field("created_at", .datetime, .required)
			.field("notation", .string, .required)
			.field("ordinal", .int, .required)
			.create()
	}

	func revert(on database: Database) -> EventLoopFuture<Void> {
		database.schema(MatchMovement.schema).delete()
	}
}
