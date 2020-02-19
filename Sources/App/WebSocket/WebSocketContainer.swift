import Vapor

enum WebSocketContainer {
	static func createWebSocket() -> NIOWebSocketServer {
		let wss = NIOWebSocketServer.default()
		return wss
	}
}
