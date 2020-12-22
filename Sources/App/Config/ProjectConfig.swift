//
//  ProjectConfig.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-21.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

enum ProjectConfig {
	struct AccessToken {
		static let expirationTime: TimeInterval = 30 * 24 * 60 * 60 // 30 days
	}

	struct SignInWithApple {
		static let applicationIdentifier = Environment.get("SIWA_APPLICATION_IDENTIFIER")
		static let servicesIdentifier = Environment.get("SIWA_SERVICES_IDENTIFIER")
		static let redirectUrl = Environment.get("SIWA_REDIRECT_URL")
	}
}
