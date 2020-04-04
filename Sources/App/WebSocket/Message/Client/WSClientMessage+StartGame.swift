//
//  WSClientMessage+StartGame.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

extension WSClientMessage {
	static func handle(playerReady: User.ID, with context: WSClientMessageContext) throws {
		guard let lobbyContext = context as? WSClientLobbyContext else {
			return context.userWS.webSocket.send(error: .invalidCommand, fromUser: context.user)
		}

		try LobbyController.shared.readyPlayer(lobbyContext)
	}
}
