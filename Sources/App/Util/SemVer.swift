//
//  SemVer.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-11-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Regex

struct SemVer {
	private static let regex = Regex(#"^(\d+)\.(\d+).(\d+)(-(([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*))?(\+(([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*))?$"#)

	let majorVersion: Int
	let minorVersion: Int
	let patchVersion: Int
	let preRelease: Metadata?
	let build: Metadata?

	init(
		majorVersion: Int,
		minorVersion: Int,
		patchVersion: Int,
		preRelease: Metadata? = nil,
		build: Metadata? = nil
	) {
		self.majorVersion = majorVersion
		self.minorVersion = minorVersion
		self.patchVersion = patchVersion
		self.preRelease = preRelease
		self.build = build
	}

	init?(rawValue: String) throws {
		guard let match = Self.regex.firstMatch(in: rawValue) else {
			throw Error.nonConformingString
		}

		guard let majorVersion = Int(match.captures[0] ?? "") else {
			throw Error.missingMajorVersion
		}

		guard let minorVersion = Int(match.captures[1] ?? "") else {
			throw Error.missingMinorVersion
		}

		guard let patchVersion = Int(match.captures[2] ?? "") else {
			throw Error.missingPatchVersion
		}

		self.majorVersion = majorVersion
		self.minorVersion = minorVersion
		self.patchVersion = patchVersion

		do {
			if let preRelease = try Metadata(rawValue: match.captures[4]) {
				self.preRelease = preRelease
			} else {
				self.preRelease = nil
			}
		} catch {
			throw Error.invalidPreReleaseMetadata
		}

		do {
			if let build = try Metadata(rawValue: match.captures[8]) {
				self.build = build
			} else {
				self.build = nil
			}
		} catch {
			throw Error.invalidBuildMetadata
		}
	}
}

// MARK: Metadata

extension SemVer {
	struct Metadata {
		fileprivate static let regex = Regex(#"^([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*$"#)

		let identifiers: [String]

		init(identifiers: [String]) {
			self.identifiers = identifiers
		}

		init?(rawValue: String?) throws {
			guard let rawValue = rawValue else { return nil }
			guard let match = Self.regex.firstMatch(in: rawValue) else {
				throw Error.invalidMetadata
			}

			self.identifiers = match.captures.compactMap {
				guard let capture = $0 else { return nil }
				return capture.starts(with: ".") ? String(capture.dropFirst(1)) : capture
			}
		}
	}
}

// MARK: Comparable

extension SemVer: Equatable, Comparable {
	static func < (lhs: Self, rhs: Self) -> Bool {
		if lhs.majorVersion != rhs.majorVersion {
			return lhs.majorVersion < rhs.majorVersion
		} else if lhs.minorVersion != rhs.minorVersion {
			return lhs.minorVersion < rhs.minorVersion
		} else if lhs.patchVersion != rhs.patchVersion {
			return lhs.patchVersion < rhs.patchVersion
		} else if lhs.preRelease != rhs.preRelease {
			if lhs.preRelease == nil, rhs.preRelease != nil {
				return true
			} else if lhs.preRelease != nil, rhs.preRelease == nil {
				return false
			} else {
				return lhs.preRelease! < rhs.preRelease!
			}
		} else if lhs.build != rhs.build {
			if lhs.build == nil, rhs.build != nil {
				return true
			} else if lhs.build != nil, rhs.build == nil {
				return false
			} else {
				return lhs.build! < rhs.build!
			}
		} else {
			return false
		}
	}
}

extension SemVer.Metadata: Equatable, Comparable {
	static func < (lhs: Self, rhs: Self) -> Bool {
		let comparison = zip(lhs.identifiers, rhs.identifiers).reduce(0) { prev, identifiers in
			guard prev == 0 else { return prev }
			let (leftId, rightId) = identifiers
			let leftAsInt = Int(leftId)
			let rightAsInt = Int(rightId)

			// Numeric identifiers have lower precedence
			if leftAsInt != nil, rightAsInt == nil {
				return -1
			} else if leftAsInt == nil, rightAsInt != nil {
				return 1
			} else if let leftAsInt = leftAsInt, let rightAsInt = rightAsInt {
				// If both are numeric, compare numerically
				if leftAsInt == rightAsInt {
					return 0
				} else if leftAsInt < rightAsInt {
					return -1
				} else {
					return 1
				}
			}

			// If neither is numeric, compare as strings
			if leftId == rightId {
				return 0
			} else if leftId < rightId {
				return -1
			} else {
				return 1
			}
		}


		if comparison == -1 {
			return true
		} else if comparison == 1 {
			return false
		} else {
			// Less identifiers has lower precedence
			return lhs.identifiers.count < rhs.identifiers.count
		}
	}
}

// MARK: Errors

extension SemVer {
	enum Error: Swift.Error {
		case nonConformingString
		case missingMajorVersion
		case missingMinorVersion
		case missingPatchVersion
		case invalidMetadata
		case invalidPreReleaseMetadata
		case invalidBuildMetadata
	}
}

// MARK: CustomStringConvertible

extension SemVer: CustomStringConvertible {
	var description: String {
		let preReleaseString: String
		if let preRelease = preRelease {
			preReleaseString = "-\(preRelease)"
		} else {
			preReleaseString = ""
		}

		let buildString: String
		if let build = build {
			buildString = "+\(build)"
		} else {
			buildString = ""
		}

		return "\(majorVersion).\(minorVersion).\(patchVersion)\(preReleaseString)\(buildString)"
	}
}

extension SemVer.Metadata: CustomStringConvertible {
	var description: String {
		identifiers.joined(separator: ".")
	}
}
