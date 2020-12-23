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
			.field("password", .string, .required)
			.field("apple_identifier", .string)
			.unique(on: "apple_identifier")
			.field("display_name", .string, .required)
			.field("elo", .int, .required)
			.field("avatar_url", .string)
			.field("is_admin", .bool)
			.field("is_guest", .bool)
			.create()
	}

	func revert(on database: Database) -> EventLoopFuture<Void> {
		database.schema(User.schema).delete()
	}
}
