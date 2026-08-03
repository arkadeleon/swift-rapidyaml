//
//  DecoderCompletionTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

private struct Base: Decodable, Equatable {
    var a: Int
    var b: Int
    var c: Int?
}

private struct Anchored: Decodable, YAMLAnchorCoding, Equatable {
    var yamlAnchor: Anchor?
    var name: String
}

private struct Tagged: Decodable, Equatable {
    var yamlTag: RapidYAML.Tag?
    var name: String
}

private final class Boxed: Decodable {
    var name: String
}

private struct Pair: Decodable {
    var first: Boxed
    var second: Boxed
}

@Suite struct MergeKeyTests {

    @Test func mergesAnAnchoredMapping() throws {
        let decoded = try YAMLDecoder().decode(Base.self, from: "base: &b {a: 1, b: 2}\n<<: *b\nc: 3\n")
        #expect(decoded == Base(a: 1, b: 2, c: 3))
    }

    @Test func mergesASequenceOfMappings() throws {
        let decoded = try YAMLDecoder().decode(Base.self, from: """
            x: &x {a: 1, b: 2}
            y: &y {b: 20, c: 30}
            <<: [*x, *y]
            """)
        // The earlier mapping in the sequence wins for `b`.
        #expect(decoded == Base(a: 1, b: 2, c: 30))
    }

    @Test func ownKeysWinOverMergedOnes() throws {
        let decoded = try YAMLDecoder().decode(Base.self, from: "base: &b {a: 1, b: 2}\n<<: *b\nb: 99\nc: 3\n")
        #expect(decoded == Base(a: 1, b: 99, c: 3))
    }

    @Test func mergeKeysAreNotThemselvesKeys() throws {
        struct Keys: Decodable {
            var all: [String]
            init(from decoder: Decoder) throws {
                all = try decoder.container(keyedBy: _YAMLCodingKey.self).allKeys.map(\.stringValue)
            }
        }
        let decoded = try YAMLDecoder().decode(Keys.self, from: "base: &b {a: 1}\n<<: *b\nc: 3\n")
        #expect(decoded.all.contains("<<") == false)
        #expect(decoded.all.sorted() == ["a", "base", "c"])
    }

    @Test func nestedMergesAreFlattened() throws {
        let decoded = try YAMLDecoder().decode(Base.self, from: """
            grand: &g {a: 1}
            parent: &p {<<: *g, b: 2}
            <<: *p
            c: 3
            """)
        #expect(decoded == Base(a: 1, b: 2, c: 3))
    }
}

@Suite struct AnchorAndTagCodingTests {

    @Test func anchorIsInjectedIntoTheContainer() throws {
        let decoded = try YAMLDecoder().decode(Anchored.self, from: "&theAnchor\nname: hi\n")
        #expect(decoded.yamlAnchor == Anchor(rawValue: "theAnchor"))
        #expect(decoded.name == "hi")
    }

    @Test func anAbsentAnchorDecodesAsNil() throws {
        #expect(try YAMLDecoder().decode(Anchored.self, from: "name: hi\n").yamlAnchor == nil)
    }

    @Test func aWrittenAnchorKeyWinsOverTheInjectedOne() throws {
        let decoded = try YAMLDecoder().decode(Anchored.self, from: "&outer\nyamlAnchor: written\nname: hi\n")
        #expect(decoded.yamlAnchor == Anchor(rawValue: "written"))
    }

    @Test func theInjectedAnchorIsNotInAllKeys() throws {
        struct Keys: Decodable {
            var all: [String]
            init(from decoder: Decoder) throws {
                all = try decoder.container(keyedBy: _YAMLCodingKey.self).allKeys.map(\.stringValue)
            }
        }
        #expect(try YAMLDecoder().decode(Keys.self, from: "&a !<!t>\nname: hi\n").all == ["name"])
    }

    @Test func tagIsInjectedIntoTheContainer() throws {
        let decoded = try YAMLDecoder().decode(Tagged.self, from: "!<!mytag>\nname: hi\n")
        #expect(decoded.yamlTag == RapidYAML.Tag("!mytag"))
    }

    @Test func anAbsentTagDecodesAsNil() throws {
        #expect(try YAMLDecoder().decode(Tagged.self, from: "name: hi\n").yamlTag == nil)
    }
}

@Suite struct AliasDereferencingTests {

    @Test func withoutAStrategyEachAliasDecodesSeparately() throws {
        let decoded = try YAMLDecoder().decode(Pair.self, from: "first: &f {name: x}\nsecond: *f\n")
        #expect(decoded.first !== decoded.second)
        #expect(decoded.first.name == decoded.second.name)
    }

    @Test func aStrategyCoalescesReferences() throws {
        let decoder = YAMLDecoder()
        decoder.options.aliasDereferencingStrategy = BasicAliasDereferencingStrategy()

        let decoded = try decoder.decode(Pair.self, from: "first: &f {name: x}\nsecond: *f\n")
        #expect(decoded.first === decoded.second)
    }

    @Test func aStrategyLeavesUnanchoredValuesAlone() throws {
        let decoder = YAMLDecoder()
        decoder.options.aliasDereferencingStrategy = BasicAliasDereferencingStrategy()

        let decoded = try decoder.decode(Pair.self, from: "first: {name: x}\nsecond: {name: x}\n")
        #expect(decoded.first !== decoded.second)
    }

    @Test func theStrategyIsReachableThroughOptions() {
        let strategy = BasicAliasDereferencingStrategy()
        let decoder = YAMLDecoder()
        decoder.options = .init(encoding: .utf8, aliasDereferencingStrategy: strategy)

        #expect(decoder.options.aliasDereferencingStrategy === strategy)
    }
}

@Suite struct DecoderMarkTests {

    private struct Marked: Decodable {
        var mark: Mark?
        var name: String

        init(from decoder: Decoder) throws {
            mark = decoder.mark
            name = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .name)
        }

        enum CodingKeys: String, CodingKey { case name }
    }

    @Test func theDecoderReportsItsNodesMark() throws {
        let decoded = try YAMLDecoder().decode(Marked.self, from: "\n\nname: hi\n")
        #expect(decoded.mark?.description == "3:1")
    }

    @Test func nestedDecodersReportTheirOwnMark() throws {
        struct Outer: Decodable {
            var inner: Marked
        }
        let decoded = try YAMLDecoder().decode(Outer.self, from: "inner:\n  name: hi\n")
        #expect(decoded.inner.mark?.description == "2:3")
    }
}
