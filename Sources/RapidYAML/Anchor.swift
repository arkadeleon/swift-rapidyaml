//
//  Anchor.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation

/// A representation of a YAML anchor see: https://yaml.org/spec/1.2.2/
/// Types interested in Encoding and Decoding Anchors should
/// conform to YAMLAnchorProviding and YAMLAnchorCoding respectively.
public final class Anchor: RawRepresentable, ExpressibleByStringLiteral, Codable, Hashable {

    /// A CharacterSet containing only characters which are permitted in an anchor name
    public static let permittedCharacters = CharacterSet.lowercaseLetters
                                                .union(.uppercaseLetters)
                                                .union(.decimalDigits)
                                                .union(.init(charactersIn: "-_"))

    /// Returns true if and only if `string` contains only characters which are also in `permittedCharacters`
    public static func isPermitted(_ string: String) -> Bool {
        Anchor.permittedCharacters.isSuperset(of: .init(charactersIn: string))
    }

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

/// Conformance of Anchor to CustomStringConvertible returns `rawValue` as `description`
extension Anchor: CustomStringConvertible {
    public var description: String { rawValue }
}
