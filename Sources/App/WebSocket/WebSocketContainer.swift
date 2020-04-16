//
//  WebSocketContainer.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Vapor

enum WebSocketContainer {
	static func createWebSocket() -> NIOWebSocketServer {
		let wss = NIOWebSocketServer.default()
		return wss
	}
}
