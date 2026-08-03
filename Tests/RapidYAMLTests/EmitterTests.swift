//
//  EmitterTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

@Suite struct RepresenterTests {

    @Test func representsScalars() throws {
        #expect(try 42.represented() == Node("42", RapidYAML.Tag(.int)))
        #expect(try true.represented() == Node("true", RapidYAML.Tag(.bool)))
        #expect(try "hello".represented() == Node("hello", RapidYAML.Tag(.str)))
        #expect(try NSNull().represented() == Node("null", RapidYAML.Tag(.null)))
        #expect(try Data("hi".utf8).represented() == Node("aGk=", RapidYAML.Tag(.binary)))
        #expect(try URL(string: "https://example.com")!.represented().string == "https://example.com")
        #expect(try Decimal(string: "1.25")!.represented().string == "1.25")
    }

    @Test func aStringThatWouldResolveToSomethingElseIsQuoted() throws {
        // `yes` would come back a bool, so it has to be written `'yes'`.
        #expect(try "yes".represented().scalar?.style == .singleQuoted)
        #expect(try "42".represented().scalar?.style == .singleQuoted)
        #expect(try "hello".represented().scalar?.style == .any)
    }

    @Test func representsContainers() throws {
        #expect(try [1, 2].represented() == Node([Node("1", RapidYAML.Tag(.int)),
                                                  Node("2", RapidYAML.Tag(.int))], RapidYAML.Tag(.seq)))

        // A dictionary has no order of its own, so it is sorted by key.
        let mapping = try ["b": 1, "a": 2].represented()
        #expect(mapping.mapping?.keys.map { $0.string } == ["a", "b"])
    }

    @Test func representsOptionals() throws {
        let some: Int? = 1
        let none: Int? = nil
        #expect(try some.represented() == Node("1", RapidYAML.Tag(.int)))
        #expect(try none.represented() == Node("null", RapidYAML.Tag(.null)))
    }

    @Test func aValueThatCannotBeRepresentedThrows() throws {
        struct Opaque {}
        #expect(throws: YAMLError.self) {
            try [Opaque()].represented()
        }
    }
}

@Suite struct DumpTests {

    @Test func dumpsScalarsAndContainers() throws {
        #expect(try dump(object: "hello") == "hello\n")
        #expect(try dump(object: 42) == "42\n")
        #expect(try dump(object: true) == "true\n")
        #expect(try dump(object: nil) == "null\n")
        #expect(try dump(object: [1, 2, 3]) == "- 1\n- 2\n- 3\n")
        #expect(try dump(object: ["b": 1, "a": 2]) == "a: 2\nb: 1\n")
    }

    @Test func aStringThatWouldReadBackAsSomethingElseIsQuoted() throws {
        #expect(try dump(object: "yes") == "'yes'\n")
        #expect(try dump(object: "42") == "'42'\n")
    }

    @Test func dumpsSeveralObjectsAsAStream() throws {
        let dumped = try dump(objects: [["a": 1], ["b": 2]])
        #expect(Array(try load_all(yaml: dumped)).count == 2)
    }

    @Test func explicitStartWritesTheMarker() throws {
        #expect(try serialize(node: Node([(Node("a"), Node("1"))]), explicitStart: true) == "---\na: 1\n")
    }

    @Test func sortKeysOrdersAMapping() throws {
        let node = Node([(Node("b"), Node("1")), (Node("a"), Node("2"))])
        #expect(try serialize(node: node) == "b: 1\na: 2\n")
        #expect(try serialize(node: node, sortKeys: true) == "a: 2\nb: 1\n")
    }

    @Test func stylesAreHonoured() throws {
        let sequence = Node([Node("1"), Node("2")], RapidYAML.Tag(.seq))
        #expect(try serialize(node: sequence, sequenceStyle: .flow) == "[1,2]\n")
        #expect(try serialize(node: sequence, sequenceStyle: .block) == "- 1\n- 2\n")

        let mapping = Node([(Node("a"), Node("1"))])
        #expect(try serialize(node: mapping, mappingStyle: .flow) == "{a: 1}\n")
    }

    @Test func anchorsAndAliasesAreWritten() throws {
        let anchor = Anchor(rawValue: "x")
        let node = Node([(Node("a"), Node("1", .implicit, .any, anchor)),
                         (Node("b"), .alias(.init(anchor)))])
        #expect(try serialize(node: node) == "a: &x 1\nb: *x\n")
    }

    /// Yams hands libYAML implicit flags that make it drop every scalar tag, so `!!binary` and
    /// custom tags are lost on the way out. Keeping them is what lets a value read back as itself.
    @Test func scalarTagsSurviveTheRoundTrip() throws {
        #expect(try dump(object: Data("hi".utf8)) == "!!binary aGk=\n")
        #expect(try load(yaml: dump(object: Data("hi".utf8))) is Data)

        #expect(try serialize(node: Node("42", RapidYAML.Tag(.str))) == "!!str 42\n")
    }

    @Test func aTagIsOmittedWhenReadingItBackWouldProduceIt() throws {
        // `42` resolves to `.int` on its own, and a quoted scalar is already a string.
        #expect(try serialize(node: Node("42", RapidYAML.Tag(.int))) == "42\n")
        #expect(try serialize(node: Node("x", RapidYAML.Tag(.str), .singleQuoted)) == "'x'\n")
    }

    @Test func blockScalarStylesAreHonoured() throws {
        #expect(try serialize(node: Node("a\nb\n", .implicit, .literal)) == "|\n  a\n  b\n")
    }
}

@Suite struct EmitterOptionTests {

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
        let emitter = Emitter()
        try emitter.open()
        try emitter.serialize(node: Node([(Node("a"), Node("1"))]))
        try emitter.close()

        #expect(String(data: emitter.data, encoding: .utf8) == "a: 1\n")
    }
}
