//
//  WSClientMessage+Forfeit.swift
//  Hive-for-iOS-server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

extension WSClientMessage {
	static func handle(playerForfeit userId: User.ID, with context: WSClientMessageContext) throws {
		guard let matchContext = context as? WSClientMatchContext else {
			return context.userWS.webSocket.send(error: .invalidCommand, fromUser: context.user)
		}

		try MatchPlayController.shared.forfeitMatch(context: matchContext)
	}
}
