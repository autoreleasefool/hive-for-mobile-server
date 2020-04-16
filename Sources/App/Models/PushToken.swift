//
//  PushToken.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor
import Fluent
import FluentSQLite

final class PushToken: Model, Content, Migration {
	typealias Database = SQLiteDatabase
	typealias ID = String

	static let idKey: IDKey = \.token

	/// Device push token
	var token: String?
	/// ID of the owner of the device push token
	private(set) var userId: User.ID
}

extension PushToken {
	/// Owner of the token
	var user: Parent<PushToken, User> {
		parent(\.userId)
	}
}

extension User {
	/// Push tokens available for the user
	var pushTokens: Children<User, PushToken> {
		children(\.userId)
	}
}
