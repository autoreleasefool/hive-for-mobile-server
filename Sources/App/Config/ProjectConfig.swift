//
//  ProjectConfig.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-21.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

enum ProjectConfig {
	static let domainHost = Environment.get("PROJECT_HOST_NAME") ?? "hiveapi.josephroque.dev"

	enum SignInWithApple {
		static let applicationIdentifier = Environment.get("SIWA_APPLICATION_IDENTIFIER")
	}
}
