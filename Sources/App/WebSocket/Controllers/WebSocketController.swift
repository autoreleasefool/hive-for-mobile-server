import Vapor

struct WebSocketContext {
	let webSocket: WebSocket
	let request: Request
}

protocol WebSocketController: class {
	func register(connection: WebSocketContext, to userid: User.ID)
	func handle(text: String, context: WSClientMessageContext)
	func handle(error: Error, on ws: WebSocketContext, context: WSClientMessageContext?)

	var activeConnections: [User.ID: WebSocketContext] { get set }
}

extension WebSocketController {
	func register(connection: WebSocketContext, to userId: User.ID) {
		activeConnections[userId] = connection
		connection.webSocket.onClose.whenComplete { [unowned self] in
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

	func handle(error: Error, on wsContext: WebSocketContext, context: WSClientMessageContext?) {
		if let serverError = error as? WSServerResponseError {
			wsContext.webSocket.send(error: serverError, fromUser: context?.user)
			context?.opponentWS?.webSocket.send(error: serverError, fromUser: context?.user)
		} else {
			wsContext.webSocket.send(error: WSServerResponseError.unknownError(error), fromUser: context?.user)
			context?.opponentWS?.webSocket.send(error: WSServerResponseError.unknownError(error), fromUser: context?.user)
		}
	}
}
