import Foundation

enum Constants {

}

public enum Env {
	private(set) static var baseURL = URL(string: "https://localhost:8080")!
	private(set) static var socketURL = URL(string: "ws://localhost:8080")!

	static func load() {
		guard let envFile = URL(string: "file://\(FileManager.default.currentDirectoryPath)")?
			.appendingPathComponent(".env") else { return }
		let contents: String
		do {
			contents = try String(contentsOf: envFile, encoding: .utf8)
		} catch {
			fatalError("Failed to read .env, \(error)")
		}

		for line in contents.split(separator: "\n") {
			let param = line.split(separator: "=")
			guard param.count == 2, param[0].count > 0 else { continue }
			let (variable, value) = (param[0], param[1])
			Env.applyValue(variable: String(variable), value: String(value))
		}
	}

	private static func applyValue(variable: String, value: String) {
		switch variable {
		case "BASE_URL": Env.baseURL = URL(string: value)!
		case "SOCKET_URL": Env.socketURL = URL(string: value)!
		default:
			print("Could not find property for \(variable)")
		}
	}
}
