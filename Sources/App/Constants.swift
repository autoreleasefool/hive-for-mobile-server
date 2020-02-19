import Foundation

enum Constants {
	#if DEBUG
	static let HOST = "localhost"
	static let PORT = 8080
	#else
	#warning("TODO: set up production HOST and PORT")
	static let HOST = "localhost"
	static let PORT = 8080
	#endif

	static let BASE_URL = URL(string: "http://\(HOST):\(PORT)")!
	static let SOCKET_URL = URL(string: "ws://\(HOST):\(PORT)")!
}
