//
//  SessionToken.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-23.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

struct SessionToken: Content {
	let userId: User.IDValue
	let sessionId: Token.IDValue
	let token: String

	init(user: User, token: Token) throws {
		self.userId = try user.requireID()
		self.sessionId = try token.requireID()
		self.token = token.value
	}

	init(userId: User.IDValue, sessionId: Token.IDValue, token: String) {
		self.userId = userId
		self.sessionId = sessionId
		self.token = token
	}
}
