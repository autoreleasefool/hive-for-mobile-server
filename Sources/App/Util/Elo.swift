//
//  Elo.swift
//  Hive-for-iOS-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Foundation

enum Elo {
	enum Outcome {
		case win
		case loss
		case draw

		var pointValue: Double {
			switch self {
			case .win: return 1
			case .loss: return 0
			case .draw: return 0.5
			}
		}
	}

	private static let kFactor: Double = 15

	struct Rating {
		static let `default` = 1000

		let playerRating: Double
		let opponentRating: Double
		let outcome: Outcome

		init(playerRating: Int, opponentRating: Int, outcome: Outcome) {
			self.playerRating = Double(playerRating)
			self.opponentRating = Double(opponentRating)
			self.outcome = outcome
		}

		var updated: Int {
			Int(round(playerRating + change))
		}

		private var expected: Double {
			1.0 / (1.0 + pow(10, (opponentRating - playerRating) / 400))
		}

		private var change: Double {
			kFactor * (outcome.pointValue - expected)
		}
	}
}
