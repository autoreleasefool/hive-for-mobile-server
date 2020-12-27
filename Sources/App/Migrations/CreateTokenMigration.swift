//
//  CreateTokenMigration.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-06-15.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent

struct CreateTokenMigration: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.schema(Token.schema)
			.field("id", .uuid, .identifier(auto: true))
			.field("user_id", .uuid, .required, .references(User.schema, "id"))
			.field("value", .string, .required)
			.unique(on: "value")
			.field("source", .int, .required)
			.field("created_at", .datetime, .required)
			.field("expires_at", .datetime)
			.create()
	}

	func revert(on database: Database) -> EventLoopFuture<Void> {
		database.schema(Token.schema).delete()
	}
}
