//
//  Populate.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent

struct PopulateWithUsers: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		_ = User(
			id: nil,
			email: "a@a.ca",
			password: "$2b$12$ByRFfmgsLcBeEqmjQR9UzeQuvXlYzbuRQENSwzo62JCuIbEvjuUCi",
			displayName: "Scott",
			elo: 192,
			avatarUrl: "https://avatars3.githubusercontent.com/u/5544925?v=4",
			isAdmin: true,
			isGuest: false
		).save(on: database)

		_ = User(
			id: nil,
			email: "b@b.ca",
			password: "$2b$12$ByRFfmgsLcBeEqmjQR9UzeQuvXlYzbuRQENSwzo62JCuIbEvjuUCi",
			displayName: "Dann Beauregard",
			elo: 1240,
			avatarUrl: "https://avatars2.githubusercontent.com/u/30088157?v=4",
			isAdmin: false,
			isGuest: false
		).save(on: database)

		return User(
			id: nil,
			email: "c@c.ca",
			password: "$2b$12$ByRFfmgsLcBeEqmjQR9UzeQuvXlYzbuRQENSwzo62JCuIbEvjuUCi",
			displayName: "Joseph",
			elo: 1000,
			avatarUrl: "https://avatars1.githubusercontent.com/u/6619581?v=4",
			isAdmin: false,
			isGuest: false
		).save(on: database)
	}

	func revert(on database: Database) -> EventLoopFuture<Void> {
		User.query(on: database)
			.filter(\.$email ~~ ["a@a.ca", "b@b.ca", "c@c.ca"])
			.delete()
	}
}
