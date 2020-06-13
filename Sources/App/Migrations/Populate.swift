//
//  Populate.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import Fluent
import FluentSQLite

struct Populate: SQLiteMigration {
	static func prepare(on conn: SQLiteConnection) -> Future<Void> {
		_ = User(
				id: nil,
				email: "a@a.ca",
				password: "$2b$12$ByRFfmgsLcBeEqmjQR9UzeQuvXlYzbuRQENSwzo62JCuIbEvjuUCi",
				displayName: "Scott",
				elo: 192,
				avatarUrl: "https://avatars3.githubusercontent.com/u/5544925?v=4",
				isBot: false,
				isAdmin: false
		).save(on: conn).transform(to: ())

		_ = User(
				id: nil,
				email: "b@b.ca",
				password: "$2b$12$ByRFfmgsLcBeEqmjQR9UzeQuvXlYzbuRQENSwzo62JCuIbEvjuUCi",
				displayName: "Dann Beauregard",
				elo: 1240,
				avatarUrl: "https://avatars2.githubusercontent.com/u/30088157?v=4",
				isBot: false,
				isAdmin: true
		).save(on: conn).transform(to: ())

		return User(
				id: UUID(uuidString: "60448917-d472-4099-b1c8-956935245d6e")!,
				email: "c@c.ca",
				password: "$2b$12$ByRFfmgsLcBeEqmjQR9UzeQuvXlYzbuRQENSwzo62JCuIbEvjuUCi",
				displayName: "Joseph",
				elo: 1000,
				avatarUrl: "https://avatars1.githubusercontent.com/u/6619581?v=4",
				isBot: false,
				isAdmin: true
		).save(on: conn).transform(to: ())
	}

	static func revert(on conn: SQLiteConnection) -> Future<Void> {
		let futures = ["a@a.ca", "b@b.ca", "c@c.ca"].map { email in
			return User.query(on: conn).filter(\User.email == email)
				.delete()
		}

		return futures.flatten(on: conn)
	}
}
