//
//  CreateUser.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-06-13.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent

struct CreateUser: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		database.schema(User.schema)
		.field("id", .uuid, .identifier(auto: true))
		.field("email", .string, .required)
		.unique(on: "email")
		.field("display_name", .string, .required)
		.field("password", .string, .required)
		.field("elo", .int, .required)
		.field("avatar_url", .string)
		.field("is_admin", .bool)
		.create()
	}

	func revert(on database: Database) -> EventLoopFuture<Void> {
		database.schema(User.schema).delete()
	}
}
