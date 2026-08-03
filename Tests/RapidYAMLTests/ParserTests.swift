//
//  ParserTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

@Suite struct LoadingTests {

    // MARK: compose

    @Test func composesASingleDocument() throws {
        let node = try #require(try RapidYAML.compose(yaml: "a: 1\nb: [x]\n"))
        #expect(node["a"]?.string == "1")
        #expect(node["b"]?.array().map { $0.string } == ["x"])
    }

    @Test func composesADocumentWithAnExplicitMarker() throws {
        let node = try #require(try RapidYAML.compose(yaml: "---\na: 1\n"))
        #expect(node["a"]?.string == "1")
    }

    @Test(arguments: ["", "\n", "# just a comment\n"])
    func aSourceWithoutDocumentsComposesToNil(yaml: String) throws {
        #expect(try RapidYAML.compose(yaml: yaml) == nil)
    }

    @Test func anEmptyDocumentComposesToAnEmptyScalar() throws {
        #expect(try RapidYAML.compose(yaml: "---\n") == Node(""))
    }

    // MARK: compose_all

    @Test func composesEveryDocumentOfAStream() throws {
        var sequence = try compose_all(yaml: "---\na: 1\n---\nb: 2\n---\nc: 3\n")
        let nodes = Array(sequence)

        #expect(nodes.count == 3)
        #expect(nodes.map { $0.mapping?.keys.first?.string } == ["a", "b", "c"])
        #expect(sequence.error == nil)
    }

    @Test func composesAStreamWithoutAnOpeningMarker() throws {
        let nodes = Array(try compose_all(yaml: "a: 1\n---\nb: 2\n"))
        #expect(nodes.count == 2)
    }

    @Test func composesAStreamOfEmptyDocuments() throws {
        #expect(Array(try compose_all(yaml: "---\n---\n")) == [Node(""), Node("")])
    }

    @Test func composesAStreamWithoutDocuments() throws {
        #expect(Array(try compose_all(yaml: "")).isEmpty)
    }

    @Test func anchorsCarryFromOneDocumentToTheNext() throws {
        // Not what the spec says, but what Yams does: the parser's anchor map is never cleared.
        let nodes = Array(try compose_all(yaml: "--- &x 1\n--- *x\n"))
        #expect(nodes.map { $0.string } == ["1", "1"])
    }

    // MARK: load

    @Test func loadsASingleDocument() throws {
        let any = try #require(try RapidYAML.load(yaml: "a: 1\nb: [x, 2.5]\n") as? [AnyHashable: Any])
        #expect(any["a"] as? Int == 1)
        #expect((any["b"] as? [Any])?.last as? Double == 2.5)
    }

    @Test func loadingASourceWithoutDocumentsGivesNil() throws {
        #expect(try RapidYAML.load(yaml: "") == nil)
    }

    @Test func loadingAnEmptyDocumentGivesNull() throws {
        #expect(try RapidYAML.load(yaml: "---\n") is NSNull)
    }

    // MARK: load_all

    @Test func loadsEveryDocumentOfAStream() throws {
        let values = Array(try load_all(yaml: "--- 1\n--- two\n--- [3]\n"))

        #expect(values.count == 3)
        #expect(values[0] as? Int == 1)
        #expect(values[1] as? String == "two")
        #expect((values[2] as? [Any])?.first as? Int == 3)
    }

    // MARK: single-document enforcement

    @Test func composeRejectsMoreThanOneDocument() throws {
        let error = #expect(throws: YAMLError.self) {
            try RapidYAML.compose(yaml: "---\na: 1\n---\nb: 2\n")
        }

        guard case .composer(let context, let problem, _, _) = try #require(error) else {
            Issue.record("expected a composer error, got \(String(describing: error))")
            return
        }
        #expect(context?.text == "expected a single document in the stream")
        #expect(problem == "but found another document")
    }

    @Test func loadRejectsMoreThanOneDocument() throws {
        #expect(throws: YAMLError.self) {
            try RapidYAML.load(yaml: "a: 1\n---\nb: 2\n")
        }
    }

    @Test func theDecoderRejectsMoreThanOneDocument() throws {
        struct Value: Decodable { var a: Int }
        #expect(throws: DecodingError.self) {
            try YAMLDecoder().decode(Value.self, from: "a: 1\n---\na: 2\n")
        }
    }
}

@Suite struct ParserTests {

    @Test func exposesWhatItWasBuiltWith() throws {
        let resolver = Resolver.basic
        let constructor = Constructor()
        let parser = try Parser(yaml: "a: 1\n", resolver: resolver, constructor: constructor, encoding: .utf8)

        #expect(parser.yaml == "a: 1\n")
        #expect(parser.resolver === resolver)
        #expect(parser.constructor === constructor)
        #expect(parser.encoding == .utf8)
    }

    @Test func nextRootWalksTheStreamAndThenStops() throws {
        let parser = try Parser(yaml: "--- 1\n--- 2\n")

        #expect(try parser.nextRoot()?.string == "1")
        #expect(try parser.nextRoot()?.string == "2")
        #expect(try parser.nextRoot() == nil)
        #expect(try parser.nextRoot() == nil, "reading past the end stays nil")
    }

    @Test func singleRootAcceptsExactlyOneDocument() throws {
        #expect(try Parser(yaml: "a: 1\n").singleRoot()?.mapping?.count == 1)
        #expect(try Parser(yaml: "").singleRoot() == nil)
        #expect(throws: YAMLError.self) {
            try Parser(yaml: "--- 1\n--- 2\n").singleRoot()
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
        let data = Data([0xED, 0xA0, 0x80])
        #expect(throws: YAMLError.self) {
            try Parser(yaml: data, encoding: .utf8)
        }
    }

    @Test func aMalformedSourceThrowsFromTheInitializer() throws {
        // rapidyaml parses the whole stream up front, so this is where the failure lands.
        #expect(throws: YAMLError.self) {
            try Parser(yaml: "a: [1\n")
        }
    }

    @Test func encodingMapsToItsSwiftEquivalent() {
        #expect(Parser.Encoding.default == .utf8)
        #expect(Parser.Encoding.utf8.swiftStringEncoding == .utf8)
        #expect(Parser.Encoding.utf16.swiftStringEncoding == .utf16)
    }

    @Test func theResolverAndConstructorReachTheComposedNodes() throws {
        var scalarMap = Constructor.defaultScalarMap
        scalarMap[.int] = { scalar in Int(scalar.string).map { $0 * 2 } }

        let parser = try Parser(yaml: "v: 21\n", resolver: .default, constructor: Constructor(scalarMap))
        #expect(try parser.singleRoot()?["v"]?.any as? Int == 42)

        let basic = try Parser(yaml: "v: 21\n", resolver: .basic)
        #expect(try basic.singleRoot()?["v"]?.tag.name == .str)
    }
}

@Suite struct YAMLSequenceTests {

    @Test func stopsAndRecordsAnErrorMidStream() throws {
        // A duplicate key is a composition failure, so the first document still arrives.
        var sequence = try compose_all(yaml: "--- {a: 1}\n--- {b: 1, b: 2}\n--- {c: 3}\n")

        // `error` has to be read off the same value that was iterated: `YAMLSequence` is a struct
        // that iterates itself, so `Array(sequence)` would advance a copy and leave this nil.
        var nodes: [Node] = []
        while let node = sequence.next() { nodes.append(node) }

        #expect(nodes.count == 1)
        #expect(sequence.error is YAMLError)
    }

    @Test func hasNoErrorWhenTheStreamIsGood() throws {
        var sequence = try compose_all(yaml: "--- 1\n--- 2\n")
        while sequence.next() != nil {}
        #expect(sequence.error == nil)
    }
}
