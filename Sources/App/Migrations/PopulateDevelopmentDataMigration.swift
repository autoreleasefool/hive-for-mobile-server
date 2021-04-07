//
//  PopulateDevelopmentDataMigration.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2021-04-07.
//  Copyright © 2021 Joseph Roque. All rights reserved.
//

import Fluent

struct PopulateDevelopmentDataMigration: Migration {
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		return User(
			appleUserIdentifier: "apple_identifier",
			displayName: "AppleUser",
			avatarUrl: nil,
			isGuest: false
		).save(on: database).flatMap {
			User(
				email: "",
				password: "",
				appleUserIdentifier: "apple_identifier_2",
				displayName: "BlankEmailAppleUser",
				elo: Elo.Rating.default,
				avatarUrl: nil,
				isAdmin: false,
				isGuest: false
			).save(on: database)
		}.flatMap {
			User(
				email: "a@a.ca",
				password: "$2b$12$ByRFfmgsLcBeEqmjQR9UzeQuvXlYzbuRQENSwzo62JCuIbEvjuUCi",
				displayName: "EmailUser",
				avatarUrl: "https://avatars.githubusercontent.com/u/6619581?v=4",
				isGuest: false
			).save(on: database)
		}
	}

	func revert(on database: Database) -> EventLoopFuture<Void> {
		return User.query(on: database)
			.filter(\.$email ~~ ["a@a.ca"])
			.delete()
			.flatMap {
				User.query(on: database)
					.filter(\.$appleUserIdentifier ~~ ["apple_identifier", "apple_identifier_2"])
					.delete()
			}
	}
}
