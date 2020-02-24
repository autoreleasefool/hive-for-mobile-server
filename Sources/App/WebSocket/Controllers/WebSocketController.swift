import Vapor

protocol WebSocketController {
	func handle(text: String, context: WSClientMessageContext)
	func handle(error: Error, on ws: WebSocket, context: WSClientMessageContext?)
}

extension WebSocketController {
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
