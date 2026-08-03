//
//  YAMLEncoderTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

private struct Everything: Codable, Equatable {
    var text: String
    var multiline: String
    var quoted: String
    var count: Int
    var negative: Int
    var ratio: Double
    var flag: Bool
    var optional: String?
    var list: [Int]
    var map: [String: String]
    var date: Date
    var data: Data
    var url: URL
    var uuid: UUID
    var decimal: Decimal
}

private let everything = Everything(
    text: "hello", multiline: "one\ntwo\n", quoted: "yes",
    count: 42, negative: -17, ratio: 1.5, flag: true,
    optional: nil, list: [1, 2, 3], map: ["b": "2", "a": "1"],
    date: Date(timeIntervalSince1970: 1_700_000_000.25),
    data: Data("hello".utf8), url: URL(string: "https://example.com")!,
    uuid: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
    decimal: Decimal(string: "1.25")!)

@Suite struct YAMLEncoderTests {

    @Test func encodesEveryScalarKindBackToItself() throws {
        let encoded = try YAMLEncoder().encode(everything)
        #expect(try YAMLDecoder().decode(Everything.self, from: encoded) == everything)
    }

    @Test func encodesAStruct() throws {
        struct Item: Encodable { var id: Int; var name: String }
        #expect(try YAMLEncoder().encode(Item(id: 501, name: "Red Potion")) == """
            id: 501
            name: Red Potion

            """)
    }

    @Test func encodesNesting() throws {
        struct Inner: Encodable { var x: [Int] }
        struct Outer: Encodable { var inner: Inner; var name: String }

        #expect(try YAMLEncoder().encode(Outer(inner: Inner(x: [1, 2]), name: "n")) == """
            inner:
              x:
                - 1
                - 2
            name: n

            """)
    }

    @Test func encodesNilAsNull() throws {
        struct Item: Encodable {
            var name: String?
            // The synthesized conformance would use `encodeIfPresent` and omit the key entirely.
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: _YAMLCodingKey.self)
                if let name {
                    try container.encode(name, forKey: _YAMLCodingKey(stringValue: "name")!)
                } else {
                    try container.encodeNil(forKey: _YAMLCodingKey(stringValue: "name")!)
                }
            }
        }

        #expect(try YAMLEncoder().encode(Item(name: nil)) == "name: null\n")
        #expect(try YAMLEncoder().encode(Item(name: "hi")) == "name: hi\n")
    }

    @Test func anOmittedOptionalLeavesNoKey() throws {
        // What the synthesized conformance does: `encodeIfPresent` skips a nil.
        struct Item: Encodable { var name: String? }
        #expect(try YAMLEncoder().encode(Item(name: nil)) == "{}\n")
    }

    @Test func encodesTopLevelScalarsAndSequences() throws {
        #expect(try YAMLEncoder().encode(42) == "42\n")
        #expect(try YAMLEncoder().encode([1, 2]) == "- 1\n- 2\n")
        #expect(try YAMLEncoder().encode(["a": 1]) == "a: 1\n")
    }

    @Test func stringsThatWouldReadBackAsSomethingElseAreQuoted() throws {
        struct Item: Codable, Equatable { var a: String; var b: String; var c: String }
        let item = Item(a: "yes", b: "42", c: "~")

        let encoded = try YAMLEncoder().encode(item)
        #expect(encoded == "a: 'yes'\nb: '42'\nc: '~'\n")
        #expect(try YAMLDecoder().decode(Item.self, from: encoded) == item)
    }

    // MARK: Options

    @Test func sortKeysOrdersTheOutput() throws {
        struct Item: Encodable { var b: Int; var a: Int }

        let encoder = YAMLEncoder()
        #expect(try encoder.encode(Item(b: 1, a: 2)) == "b: 1\na: 2\n")

        encoder.options.sortKeys = true
        #expect(try encoder.encode(Item(b: 1, a: 2)) == "a: 2\nb: 1\n")
    }

    @Test func containerStylesApply() throws {
        struct Item: Encodable { var list: [Int] }

        let encoder = YAMLEncoder()
        encoder.options.sequenceStyle = .flow
        #expect(try encoder.encode(Item(list: [1, 2])) == "list: [1,2]\n")
    }

    @Test func newlineScalarStyleApplies() throws {
        struct Item: Codable, Equatable { var text: String }
        let item = Item(text: "one\ntwo\n")

        let encoder = YAMLEncoder()
        encoder.options.newLineScalarStyle = .literal

        let encoded = try encoder.encode(item)
        #expect(encoded == "text: |\n  one\n  two\n")
        #expect(try YAMLDecoder().decode(Item.self, from: encoded) == item)
    }

    @Test func explicitStartApplies() throws {
        let encoder = YAMLEncoder()
        encoder.options.explicitStart = true
        #expect(try encoder.encode(["a": 1]) == "---\na: 1\n")
    }

    @Test func anUnsupportedOptionMakesEncodingFail() throws {
        let encoder = YAMLEncoder()
        encoder.options.canonical = true
        #expect(throws: EncodingError.self) {
            try encoder.encode(["a": 1])
        }
    }

    // MARK: Anchors and tags

    @Test func anAnchorProvidedByTheValueIsWritten() throws {
        struct Item: Encodable, YAMLAnchorProviding {
            var yamlAnchor: Anchor?
            var name: String
        }

        #expect(try YAMLEncoder().encode(Item(yamlAnchor: "theAnchor", name: "hi")) == "&theAnchor\nname: hi\n")
    }

    @Test func aTagProvidedByTheValueIsWritten() throws {
        struct Item: Encodable, YAMLTagProviding {
            var yamlTag: RapidYAML.Tag?
            var name: String
        }

        #expect(try YAMLEncoder().encode(Item(yamlTag: RapidYAML.Tag("!custom"), name: "hi")) == "!custom\nname: hi\n")
    }

    @Test func anchorsRoundTripThroughTheDecoder() throws {
        struct Item: Codable, Equatable, YAMLAnchorCoding {
            var yamlAnchor: Anchor?
            var name: String
        }
        let item = Item(yamlAnchor: "x", name: "hi")

        let encoded = try YAMLEncoder().encode(item)
        #expect(try YAMLDecoder().decode(Item.self, from: encoded) == item)
    }
}

@Suite struct RedundancyAliasingTests {

    private struct Pair: Encodable {
        var first: [String: String]
        var second: [String: String]
    }

    private let pair = Pair(first: ["a": "1"], second: ["a": "1"])

    @Test func withoutAStrategyRedundantValuesAreWrittenTwice() throws {
        #expect(try YAMLEncoder().encode(pair) == "first:\n  a: '1'\nsecond:\n  a: '1'\n")
    }

    @Test func hashableAliasingWritesAnAnchorAndAnAlias() throws {
        let encoder = YAMLEncoder()
        encoder.options.redundancyAliasingStrategy = HashableAliasingStrategy()

        let encoded = try encoder.encode(pair)
        #expect(encoded.contains("&"))
        #expect(encoded.contains("*"))

        // What it aliases has to survive being read back.
        let loaded = try #require(try load(yaml: encoded) as? [AnyHashable: Any])
        #expect((loaded["second"] as? [AnyHashable: Any])?["a"] as? String == "1")
    }

    @Test func strictEncodableAliasingAliasesByEncodedForm() throws {
        let encoder = YAMLEncoder()
        encoder.options.redundancyAliasingStrategy = StrictEncodableAliasingStrategy()

        let encoded = try encoder.encode(pair)
        let loaded = try #require(try load(yaml: encoded) as? [AnyHashable: Any])
        #expect((loaded["first"] as? [AnyHashable: Any])?["a"] as? String == "1")
        #expect((loaded["second"] as? [AnyHashable: Any])?["a"] as? String == "1")
    }

    @Test func aValuesOwnAnchorIsUsedAsTheAliasName() throws {
        struct Anchored: Encodable, Hashable, YAMLAnchorProviding {
            var yamlAnchor: Anchor?
            var name: String
        }
        struct Pair: Encodable {
            var first: Anchored
            var second: Anchored
        }

        let value = Anchored(yamlAnchor: "shared", name: "hi")
        let encoder = YAMLEncoder()
        encoder.options.redundancyAliasingStrategy = HashableAliasingStrategy()

        let encoded = try encoder.encode(Pair(first: value, second: value))
        #expect(encoded.contains("&shared"))
        #expect(encoded.contains("*shared"))
    }

    @Test func aStrategyCanBeReusedAcrossDocuments() throws {
        let strategy = HashableAliasingStrategy()
        let encoder = YAMLEncoder()
        encoder.options.redundancyAliasingStrategy = strategy

        let first = try encoder.encode(pair)
        let second = try encoder.encode(pair)

        // The anchor map is released between documents, so the second document names its own
        // anchors rather than aliasing into the first. The counter itself keeps going, as in Yams.
        #expect(first != second)
        for encoded in [first, second] {
            let loaded = try #require(try load(yaml: encoded) as? [AnyHashable: Any])
            #expect((loaded["second"] as? [AnyHashable: Any])?["a"] as? String == "1")
        }
    }
}
