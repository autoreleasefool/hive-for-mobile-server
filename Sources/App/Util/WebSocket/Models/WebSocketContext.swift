//
//  WebSocketContext.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-11-29.
//

import Vapor

struct WebSocketContext {
	let webSocket: WebSocket
	let request: Request
}
