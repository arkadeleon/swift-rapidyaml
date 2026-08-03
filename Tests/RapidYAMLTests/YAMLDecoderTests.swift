//
//  YAMLDecoderTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2025/6/12.
//

import Foundation
import Testing
@testable import RapidYAML

struct Item: Decodable {
    var id: Int
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

@Test func decoder() async throws {
    let yamlString = """
        - Id: 501
          Name: Red Potion
          Type: Healing
          Buy: 10
          Weight: 70
          Script: |
            itemheal rand(45,65),0;
        - Id: 502
          Name: Orange Potion
          Type: Healing
          Buy: 50
          Weight: 100
          Script: |
            itemheal rand(105,145),0;
        
        """
    let yamlData = yamlString.data(using: .utf8)!

    let decoder = YAMLDecoder()
    let items = try decoder.decode([Item].self, from: yamlData)

    #expect(items.count == 2)
    #expect(items[0].id == 501)
    #expect(items[0].name == "Red Potion")
    #expect(items[1].id == 502)
    #expect(items[1].name == "Orange Potion")
}

@Test func decodesFromANode() async throws {
    let node = try #require(try Composer.compose(yaml: "Id: 501\nName: Red Potion\n"))
    let item = try YAMLDecoder().decode(Item.self, from: node)

    #expect(item.id == 501)
    #expect(item.name == "Red Potion")
}

@Test func decodesThroughAliases() async throws {
    struct Potions: Decodable {
        var red: Item
        var also: Item
    }

    let potions = try YAMLDecoder().decode(Potions.self, from: """
        red: &potion
          Id: 501
          Name: Red Potion
        also: *potion
        """)

    #expect(potions.also.id == 501)
    #expect(potions.also.name == "Red Potion")
}

struct Nullable: Decodable {
    var name: String?
}

/// The resolver's null rule is what makes `~` and `null` decode as nil, not just an empty value.
@Test(arguments: ["name:\n", "name: ~\n", "name: null\n", "name: Null\n", "name: NULL\n"])
func decodesNullAsNil(yamlString: String) async throws {
    #expect(try YAMLDecoder().decode(Nullable.self, from: yamlString).name == nil)
}

/// Only a plain scalar is null — quoting it makes it the string, as in Yams.
@Test(arguments: ["name: 'null'\n", "name: \"~\"\n"])
func decodesQuotedNullAsAString(yamlString: String) async throws {
    #expect(try YAMLDecoder().decode(Nullable.self, from: yamlString).name != nil)
}

/// Decoding used to go through `Int(_:)` and `Bool(_:)`, which only understand base 10 and
/// `true`/`false`. It goes through `ScalarConstructible` now.
@Test func decodesTheFullScalarSyntax() async throws {
    struct Values: Decodable {
        var hex: Int
        var octal: Int
        var binary: Int
        var separated: Int
        var sexagesimal: Int
        var narrow: Int8
        var unsigned: UInt16
        var yes: Bool
        var off: Bool
        var infinity: Double
        var notANumber: Double
        var small: Float
    }

    let values = try YAMLDecoder().decode(Values.self, from: """
        hex: 0x1F
        octal: 0o17
        binary: 0b1010
        separated: 1_000_000
        sexagesimal: 1:30
        narrow: -128
        unsigned: 65535
        yes: yes
        off: Off
        infinity: -.inf
        notANumber: .nan
        small: 1.5e-3
        """)

    #expect(values.hex == 31)
    #expect(values.octal == 15)
    #expect(values.binary == 10)
    #expect(values.separated == 1_000_000)
    #expect(values.sexagesimal == 90)
    #expect(values.narrow == -128)
    #expect(values.unsigned == 65535)
    #expect(values.yes)
    #expect(!values.off)
    #expect(values.infinity == -.infinity)
    #expect(values.notANumber.isNaN)
    #expect(values.small == 1.5e-3)
}

@Test func decodesFoundationScalars() async throws {
    struct Values: Decodable {
        var date: Date
        var data: Data
        var uuid: UUID
        var decimal: Decimal
        var url: URL
    }

    let values = try YAMLDecoder().decode(Values.self, from: """
        date: 2026-08-03T11:22:33Z
        data: !!binary aGVsbG8=
        uuid: E621E1F8-C36C-495A-93FC-0C247A3E6E5F
        decimal: 1.25
        url: https://example.com
        """)

    #expect(values.date == DateComponents(calendar: Calendar(identifier: .gregorian),
                                          timeZone: TimeZone(secondsFromGMT: 0),
                                          year: 2026, month: 8, day: 3,
                                          hour: 11, minute: 22, second: 33).date)
    #expect(String(data: values.data, encoding: .utf8) == "hello")
    #expect(values.uuid == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    #expect(values.decimal == Decimal(string: "1.25"))
    #expect(values.url == URL(string: "https://example.com"))
}

@Test func quotedScalarsDecodeAsStrings() async throws {
    struct Values: Decodable {
        var quoted: String
    }

    // A quoted scalar is never resolved by value, so this is not a type mismatch.
    #expect(try YAMLDecoder().decode(Values.self, from: "quoted: '42'\n").quoted == "42")
}

@Test func aScalarThatCannotConstructIsATypeMismatch() async throws {
    struct Values: Decodable {
        var count: Int
    }

    #expect(throws: DecodingError.self) {
        try YAMLDecoder().decode(Values.self, from: "count: not a number\n")
    }
}

@Test func duplicateKeysFailToDecode() async throws {
    #expect(throws: DecodingError.self) {
        try YAMLDecoder().decode(Item.self, from: "Id: 501\nName: Red\nId: 502\n")
    }
}

/// Malformed YAML used to abort the process inside rapidyaml's default error callbacks.
@Test(arguments: [
    "Id: 501\n  Name: Red Potion\n",
    "Id: [501, 502\n",
    "\t- Id: 501\n",
])
func decoderThrowsOnMalformedYAML(yamlString: String) async throws {
    let decoder = YAMLDecoder()

    #expect(throws: DecodingError.self) {
        try decoder.decode(Item.self, from: yamlString)
    }
}

@Test func malformedYAMLErrorLocatesTheFailure() async throws {
    let yamlString = "Id: 501\n  Name: Red Potion\n"

    let error = #expect(throws: DecodingError.self) {
        try YAMLDecoder().decode(Item.self, from: yamlString)
    }

    guard case .dataCorrupted(let context) = error else {
        Issue.record("expected a dataCorrupted error, got \(String(describing: error))")
        return
    }

    let yamlError = try #require(context.underlyingError as? YAMLError)
    guard case .parser(let errorContext, let problem, let mark, let yaml) = yamlError else {
        Issue.record("expected a parser error, got \(yamlError)")
        return
    }

    // rapidyaml has no equivalent of libYAML's error context.
    #expect(errorContext == nil)
    #expect(problem == "multiline scalars cannot be used as keys")
    #expect(mark.line == 2)
    #expect(mark.column == 7)
    #expect(yaml == yamlString)

    #expect(yamlError.description == """
        2:7: error: parser: multiline scalars cannot be used as keys:
          Name: Red Potion
              ^
        """)
}

/// rapidyaml reports columns in bytes, `Mark` reports them in `UnicodeScalar`.
@Test func malformedYAMLErrorColumnCountsUnicodeScalars() async throws {
    // The `}` sits at scalar column 12, but at byte column 20.
    let error = #expect(throws: DecodingError.self) {
        try YAMLDecoder().decode(Item.self, from: "紅色藥水: [1, 2}\n")
    }

    guard case .dataCorrupted(let context) = error,
          case .parser(_, _, let mark, _) = try #require(context.underlyingError as? YAMLError) else {
        Issue.record("expected a parser error, got \(String(describing: error))")
        return
    }

    #expect(mark.line == 1)
    #expect(mark.column == 12)
}

@Test func errorDescriptionsMatchYams() async throws {
    let yaml = "a: 1\nb: 2\n"
    let mark = Mark(line: 2, column: 4)

    #expect(YAMLError.no.description == "No error is produced")
    #expect(YAMLError.memory.description == "Memory error")
    #expect(YAMLError.writer(problem: "broken").description == "broken")
    #expect(YAMLError.emitter(problem: "broken").description == "broken")
    #expect(YAMLError.representer(problem: "broken").description == "broken")
    #expect(YAMLError.dataCouldNotBeDecoded(encoding: .utf8).description
        == "String could not be decoded from data using 'Unicode (UTF-8)' encoding")

    #expect(YAMLError.reader(problem: "broken", offset: 5, value: -1, yaml: yaml).description == """
        2:1: error: reader: broken:
        b: 2
        ^
        """)
    #expect(YAMLError.reader(problem: "broken", offset: nil, value: 42, yaml: yaml).description
        == "broken at offset: nil, value: 42")

    let errorContext = YAMLError.Context(text: "while parsing a block mapping", mark: Mark(line: 1, column: 1))
    #expect(YAMLError.scanner(context: errorContext, problem: "broken", mark, yaml: yaml).description == """
        2:4: error: scanner: while parsing a block mapping in line 1, column 1
        broken:
        b: 2
           ^
        """)
    #expect(YAMLError.composer(context: nil, problem: "broken", mark, yaml: yaml).description == """
        2:4: error: composer: broken:
        b: 2
           ^
        """)
    #expect(YAMLError.duplicatedKeysInMapping(duplicates: ["b", "a"], context: errorContext).description == """
        Parser: expected all keys to be unique but found the following duplicated key(s): 'a', 'b'.
        Context:
        while parsing a block mapping in line 1, column 1

        """)
}
