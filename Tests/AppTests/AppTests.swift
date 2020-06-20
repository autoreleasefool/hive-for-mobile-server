//
//  AppTests.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-06-20.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

@testable import App
import XCTVapor

final class AppTests: XCTestCase {
	func testItWorks() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)

		try app.test(.GET, "/") { res in
			XCTAssertEqual(res.status, .ok)
			XCTAssertEqual(res.body.string, "It works!")
		}
	}
}
