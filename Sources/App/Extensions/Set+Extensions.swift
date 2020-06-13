//
//  Set+Extensions.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

extension Set {
	mutating func set(_ value: Element, to included: Bool) {
		if included {
			self.insert(value)
		} else {
			self.remove(value)
		}
	}
}
