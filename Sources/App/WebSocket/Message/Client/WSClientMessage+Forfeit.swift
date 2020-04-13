//
//  WSClientMessage+Forfeit.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

extension WSClientMessage {
	static func handle(playerForfeit userId: User.ID, with context: WSClientMessageContext) throws {
		if let matchContext = context as? WSClientMatchContext {
			try MatchPlayController.shared.forfeitMatch(context: matchContext)
		} else if let lobbyContext = context as? WSClientLobbyContext {
			try LobbyController.shared.leaveMatch(context: lobbyContext)
		} else {
			context.userWS.webSocket.send(error: .invalidCommand, fromUser: context.user)
		}
	}
}
