//
//  GameState+Extensions.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import HiveEngine

extension GameState.Option {
	static func parse(_ string: String) -> Set<GameState.Option> {
		var options: Set<GameState.Option> = []
		string.split(separator: ";").forEach {
			let optionAndValue = $0.split(separator: ":")
			guard optionAndValue.count == 2 else { return }
			if Bool(String(optionAndValue[1])) ?? false,
				let option = GameState.Option(rawValue: String(optionAndValue[0])) {
				options.insert(option)
			}
		}
		return options
	}

	static func encode(_ options: Set<GameState.Option>) -> String {
		GameState.Option.allCases
			.map { "\($0.rawValue):\(options.contains($0))" }
			.joined(separator: ";")
	}
}
