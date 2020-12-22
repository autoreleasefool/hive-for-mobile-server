//
//  ProjectConfig.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-12-21.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

enum ProjectConfig {
	struct SignInWithApple {
		static let applicationIdentifier = Environment.get("SIWA_APPLICATION_IDENTIFIER")
	}
}
