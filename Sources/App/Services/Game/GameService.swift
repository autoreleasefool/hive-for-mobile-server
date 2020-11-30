//
//  GameService.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-11-29.
//

import Vapor

protocol GameService {
	var activeGames: [Game] { get }

	func addGame(_ game: Game, on req: Request) throws -> EventLoopFuture<Void>
	func addUser(_ user: User, to match: Match, on req: Request) throws -> EventLoopFuture<Void>

	func connectPlayer(_ user: User, ws: WebSocket, on req: Request) throws
	func connectSpectator(_ user: User, ws: WebSocket, on req: Request) throws
}

// MARK: - Storage

struct GameServiceKey: StorageKey {
	typealias Value = GameService
}

extension Application {
	var gameService: GameService {
		get {
			self.storage[GameServiceKey.self]!
		}
		set {
			self.storage[GameServiceKey.self] = newValue
		}
	}
}
