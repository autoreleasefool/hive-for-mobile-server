//
//  User+Authentication.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-21.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

extension User: Authenticatable {}

extension User {
	enum Authentication {}
	enum SignInWithApple {}
}

extension User.Authentication {
	struct Response: Content {
		let accessToken: String?
		let user: User.Public.Summary
	}
}

extension User.SignInWithApple {
	struct Request: Content {
		let appleIdentityToken: String
		let displayName: String?
		let avatarUrl: String?
	}
}

extension User.SignInWithApple.Request: Validatable {
	static func validations(_ validations: inout Validations) {
		validations.add("displayName", as: String?.self, is: .nil || (.alphanumeric && .count(3...24)))
		validations.add("avatarUrl", as: String?.self, is: .nil || .url)
	}
}

// MARK: - Logout

extension User {
	enum Logout {}
}

extension User.Logout {
	struct Response: Content {
		let success: Bool
	}
}
