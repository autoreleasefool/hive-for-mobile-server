import Vapor

protocol WebSocketController: class {
	func register(connection: WebSocket, to userid: User.ID)
	func handle(text: String, context: WSClientMessageContext)
	func handle(error: Error, on ws: WebSocket, context: WSClientMessageContext?)

	var activeConnections: [User.ID: WebSocket] { get set }
}

extension WebSocketController {
	func register(connection: WebSocket, to userId: User.ID) {
		activeConnections[userId] = connection
		connection.onClose.whenComplete { [unowned self] in
			self.unregister(userId: userId)
		}
	}

	func unregister(userId: User.ID) {
		activeConnections[userId] = nil
	}

	func handle(text: String, context: WSClientMessageContext) {
		do {
			try WSClientMessage.init(from: text).handle(context)
		} catch {
			self.handle(error: error, on: context.userWS, context: context)
		}
	}

	func handle(error: Error, on ws: WebSocket, context: WSClientMessageContext?) {
		if let serverError = error as? WSServerResponseError {
			// Error can be gracefully handled
		} else {

		}
	}
}
