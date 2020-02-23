extension Set {
	mutating func set(_ value: Element, to included: Bool) {
		if included {
			self.insert(value)
		} else {
			self.remove(value)
		}
	}
}
