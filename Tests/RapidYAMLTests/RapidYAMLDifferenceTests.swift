//
//  RapidYAMLDifferenceTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

/// Where this library deliberately parts company with Yams, and the API shapes that are its own.
///
/// Everything Yams' own suite already covers lives in `Ported/`; this is what that suite cannot
/// express, because the behaviour is either better than Yams' or simply different.
@Suite struct RapidYAMLDifferenceTests {

    // MARK: Composition

    @Test func mappingsKeepTheirSourceOrder() throws {
        // The Objective-C bridge used to build mappings into an NSMutableDictionary, which made
        // this order non-deterministic.
        let node = try #require(try RapidYAML.compose(yaml: "{delta: 1, alpha: 2, charlie: 3, bravo: 4}"))
        #expect(node.mapping?.keys.map { $0.string } == ["delta", "alpha", "charlie", "bravo"])
    }

    @Test func collectionStylesAreReal() throws {
        // Yams reports `.any` for every container, because it reads the style off libYAML's *end*
        // event, which does not carry one. rapidyaml tells us the style that was written.
        #expect(try RapidYAML.compose(yaml: "{a: 1}")?.mapping?.style == .flow)
        #expect(try RapidYAML.compose(yaml: "a: 1\n")?.mapping?.style == .block)
        #expect(try RapidYAML.compose(yaml: "[1]")?.sequence?.style == .flow)
        #expect(try RapidYAML.compose(yaml: "- 1\n")?.sequence?.style == .block)
    }

    @Test func tagsAreNormalisedToTheirLongForm() throws {
        // rapidyaml reports a tag as written; libYAML resolves it. The bridge normalises so that
        // both spellings arrive as the same `Tag.Name`.
        let node = try #require(try RapidYAML.compose(yaml: """
            a: !!int 5
            b: !<tag:yaml.org,2002:bool> true
            c: !custom 7
            """))

        #expect(node["a"]?.tag.name == .int)
        #expect(node["b"]?.tag.name == .bool)
        #expect(node["c"]?.tag.name == RapidYAML.Tag.Name(rawValue: "!custom"), "non-schema tags pass through")
    }

    @Test func marksCountColumnsInUnicodeScalars() throws {
        // rapidyaml reports the value at byte column 11; `藥水` starts at scalar column 5.
        let node = try #require(try RapidYAML.compose(yaml: "紅色: 藥水\n"))
        #expect(node.mapping?[0].value.mark?.description == "1:5")
    }

    @Test func anchorsCarryFromOneDocumentToTheNext() throws {
        // Not what the spec says, but what Yams does: the parser's anchor map is never cleared.
        #expect(Array(try compose_all(yaml: "--- &x 1\n--- *x\n")).map { $0.string } == ["1", "1"])
    }

    // MARK: Parser

    @Test func aMalformedSourceThrowsFromTheInitializer() throws {
        // rapidyaml parses the whole stream up front, where libYAML is an event loop, so a
        // failure lands here rather than in `nextRoot()`.
        #expect(throws: YAMLError.self) {
            try Parser(yaml: "a: [1\n")
        }
    }

    @Test func parsesFromData() throws {
        let data = try #require("a: 1\n".data(using: .utf8))
        #expect(try Parser(yaml: data).singleRoot()?["a"]?.string == "1")

        let utf16 = try #require("a: 1\n".data(using: .utf16))
        #expect(try Parser(yaml: utf16, encoding: .utf16).singleRoot()?["a"]?.string == "1")
    }

    @Test func dataThatCannotBeDecodedThrows() throws {
        // A lone high surrogate is not valid UTF-8.
        #expect(throws: YAMLError.self) {
            try Parser(yaml: Data([0xED, 0xA0, 0x80]), encoding: .utf8)
        }
    }

    @Test func encodingMapsToItsSwiftEquivalent() {
        // `Parser.Encoding.default` is plainly `.utf8` here; Yams' reads an environment variable
        // and prints to stdout when it fires.
        #expect(Parser.Encoding.default == .utf8)
        #expect(Parser.Encoding.utf8.swiftStringEncoding == .utf8)
        #expect(Parser.Encoding.utf16.swiftStringEncoding == .utf16)
    }

    @Test func aSequenceRecordsItsErrorOnTheValueThatWasIterated() throws {
        var sequence = try compose_all(yaml: "--- {a: 1}\n--- {b: 1, b: 2}\n--- {c: 3}\n")

        // `YAMLSequence` is a struct that iterates itself, so `Array(sequence)` would advance a
        // copy and leave `error` nil on the original.
        var nodes: [Node] = []
        while let node = sequence.next() { nodes.append(node) }

        #expect(nodes.count == 1)
        #expect(sequence.error is YAMLError)
    }

    // MARK: Emitting

    @Test func scalarTagsSurviveTheRoundTrip() throws {
        // Yams hands libYAML implicit flags that make it drop every scalar tag, so `!!binary` and
        // custom tags are lost on the way out. Keeping them is what lets a value read back as
        // itself.
        #expect(try dump(object: Data("hi".utf8)) == "!!binary aGk=\n")
        #expect(try load(yaml: dump(object: Data("hi".utf8))) is Data)

        #expect(try serialize(node: Node("42", RapidYAML.Tag(.str))) == "!!str 42\n")
    }

    @Test func aTagIsOmittedWhenReadingItBackWouldProduceIt() throws {
        #expect(try serialize(node: Node("42", RapidYAML.Tag(.int))) == "42\n")
        #expect(try serialize(node: Node("x", RapidYAML.Tag(.str), .singleQuoted)) == "'x'\n")
    }

    @Test func aTagWithoutAHandleIsWrittenVerbatim() throws {
        // `!<name>` is what reads back as that same name; `!name` would read back as `!name`.
        #expect(try serialize(node: Node("v", RapidYAML.Tag("custom"))) == "!<custom> v\n")
        #expect(try serialize(node: Node("v", RapidYAML.Tag("!custom"))) == "!custom v\n")
    }

    /// rapidyaml emits a whole tree at a time and has no equivalent of libYAML's formatting
    /// controls, so asking for one is refused rather than quietly ignored.
    @Test func unsupportedOptionsAreRejected() throws {
        let unsupported: [(String, Emitter.Options)] = [
            ("canonical", .init(canonical: true)),
            ("indent", .init(indent: 2)),
            ("width", .init(width: 80)),
            ("explicitEnd", .init(explicitEnd: true)),
            ("version", .init(version: (major: 1, minor: 2))),
            ("lineBreak", .init(lineBreak: .crln)),
        ]

        for (name, options) in unsupported {
            #expect(options.unsupportedOption == name)

            let emitter = Emitter()
            emitter.options = options
            #expect(throws: YAMLError.self, "\(name) should be rejected") {
                try emitter.open()
            }
        }

        let encoder = YAMLEncoder()
        encoder.options.canonical = true
        #expect(throws: EncodingError.self) {
            try encoder.encode(["a": 1])
        }
    }

    @Test func supportedOptionsAreAccepted() throws {
        let emitter = Emitter(allowUnicode: true, explicitStart: true, sortKeys: true,
                              sequenceStyle: .flow, mappingStyle: .block, newLineScalarStyle: .literal)
        #expect(emitter.options.unsupportedOption == nil)
        try emitter.open()
        try emitter.close()
    }

    @Test func theEmitterRefusesToBeUsedOutOfOrder() throws {
        let emitter = Emitter()
        #expect(throws: YAMLError.self) { try emitter.serialize(node: Node("a")) }
        #expect(throws: YAMLError.self) { try emitter.close() }

        try emitter.open()
        #expect(throws: YAMLError.self) { try emitter.open() }

        try emitter.close()
        #expect(throws: YAMLError.self) { try emitter.serialize(node: Node("a")) }
        try emitter.close() // closing twice is a no-op
    }

    @Test func theEmitterHoldsItsOutput() throws {
        // Nothing is written until `close()`: rapidyaml needs the whole stream before it emits.
        let emitter = Emitter()
        try emitter.open()
        try emitter.serialize(node: Node([(Node("a"), Node("1"))]))
        #expect(emitter.data.isEmpty)

        try emitter.close()
        #expect(String(data: emitter.data, encoding: .utf8) == "a: 1\n")
    }

    @Test func onlyAliasedAnchorsMintedByAStrategyAreWritten() throws {
        // Yams sheds unreferenced anchors by accident — its `Node.anchor` is `weak`. Anchors are
        // held strongly here, so the encoder drops them deliberately.
        struct Pair: Encodable {
            var first: [String: String]
            var second: [String: String]
        }

        let encoder = YAMLEncoder()
        encoder.options.redundancyAliasingStrategy = HashableAliasingStrategy()

        let encoded = try encoder.encode(Pair(first: ["a": "1"], second: ["a": "1"]))
        #expect(encoded == "first: &1\n  a: '1'\nsecond: *1\n")
    }
}
