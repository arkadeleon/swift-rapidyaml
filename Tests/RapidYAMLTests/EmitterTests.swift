//
//  EmitterTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import XCTest
@testable import RapidYAML

final class EmitterTests: XCTestCase, @unchecked Sendable {

    func testScalar() throws {
        var node: Node = "key"

        let expectedAnyAndPlain = "key\n"
        node.scalar?.style = .any
        XCTAssertEqual(try RapidYAML.serialize(node: node), expectedAnyAndPlain)
        node.scalar?.style = .plain
        XCTAssertEqual(try RapidYAML.serialize(node: node), expectedAnyAndPlain)
        node.scalar?.style = .singleQuoted
        XCTAssertEqual(try RapidYAML.serialize(node: node), "'key'\n")

        node.scalar?.style = .doubleQuoted
        XCTAssertEqual(try RapidYAML.serialize(node: node), "\"key\"\n")
        node.scalar?.style = .literal
        XCTAssertEqual(try RapidYAML.serialize(node: node), "|-\n  key\n")
        node.scalar?.style = .folded
        XCTAssertEqual(try RapidYAML.serialize(node: node), ">-\n  key\n")
    }

    func testSequence() throws {
        var node: Node = ["a", "b", "c"]

        let expectedAnyIsBlock = """
            - a
            - b
            - c

            """
        node.sequence?.style = .any
        XCTAssertEqual(try RapidYAML.serialize(node: node), expectedAnyIsBlock)
        node.sequence?.style = .block
        XCTAssertEqual(try RapidYAML.serialize(node: node), expectedAnyIsBlock)

        node.sequence?.style = .flow
        // rapidyaml writes no space after a flow separator.
        XCTAssertEqual(try RapidYAML.serialize(node: node), "[a,b,c]\n")
    }

    /// rapidyaml always indents by two spaces and has no equivalent of libYAML's `indent`, so the
    /// option is refused rather than ignored. It also indents a sequence under a mapping key,
    /// where libYAML leaves it at the parent's column.
    func testIndentation() throws {
        let node: Node = ["key1": ["key2": ["a", "b"]]]
        XCTAssertEqual(try RapidYAML.serialize(node: node), """
            key1:
              key2:
                - a
                - b

            """)

        for indent in [-2, -1, 4, 9, 10] {
            XCTAssertThrowsError(try RapidYAML.serialize(node: node, indent: indent))
        }
        // 0 is the default, so it is accepted.
        XCTAssertNoThrow(try RapidYAML.serialize(node: node, indent: 0))
    }

    func testMapping() throws {
        var node: Node = ["key1": "value1", "key2": "value2"]

        let expectedAnyIsBlock = """
            key1: value1
            key2: value2

            """
        node.mapping?.style = .any
        XCTAssertEqual(try RapidYAML.serialize(node: node), expectedAnyIsBlock)
        node.mapping?.style = .block
        XCTAssertEqual(try RapidYAML.serialize(node: node), expectedAnyIsBlock)

        node.mapping?.style = .flow
        // rapidyaml writes no space after a flow separator.
        XCTAssertEqual(try RapidYAML.serialize(node: node), "{key1: value1,key2: value2}\n")
    }

    /// rapidyaml always writes `\n`, so anything else is refused rather than ignored.
    func testLineBreaks() throws {
        let node: Node = "key"
        XCTAssertEqual(try RapidYAML.serialize(node: node, lineBreak: .ln), "key\n")
        XCTAssertThrowsError(try RapidYAML.serialize(node: node, lineBreak: .cr))
        XCTAssertThrowsError(try RapidYAML.serialize(node: node, lineBreak: .crln))
    }

    /// libYAML escapes non-ASCII unless `allowUnicode` is set, and escapes anything outside the
    /// BMP regardless. rapidyaml has no escaping mode: it always writes the characters through,
    /// which is what `allowUnicode: true` asks for.
    func testAllowUnicode() throws {
        for allowUnicode in [false, true] {
            XCTAssertEqual(try RapidYAML.serialize(node: "あ", allowUnicode: allowUnicode), "あ\n")
            XCTAssertEqual(try RapidYAML.serialize(node: "😀", allowUnicode: allowUnicode), "😀\n")
        }
    }

    func testSortKeys() throws {
        let node: Node = [
            "key3": "value3",
            "key2": "value2",
            "key1": "value1"
        ]
        let yaml = try RapidYAML.serialize(node: node)
        let expected = "key3: value3\nkey2: value2\nkey1: value1\n"
        XCTAssertEqual(yaml, expected)
        let yamlSorted = try RapidYAML.serialize(node: node, sortKeys: true)
        let expectedSorted = "key1: value1\nkey2: value2\nkey3: value3\n"
        XCTAssertEqual(yamlSorted, expectedSorted)
    }

    func testSmartQuotedString() throws {
        struct Sample {
            let string: String
            let tag: Tag.Name
            let expected: String
            let line: UInt
        }
        let samples = [
            Sample(string: "string", tag: .str, expected: "string", line: #line),
            Sample(string: "true", tag: .bool, expected: "'true'", line: #line),
            Sample(string: "1", tag: .int, expected: "'1'", line: #line),
            Sample(string: "1.0", tag: .float, expected: "'1.0'", line: #line),
            Sample(string: "null", tag: .null, expected: "'null'", line: #line),
            Sample(string: "2019-07-06", tag: .timestamp, expected: "'2019-07-06'", line: #line)
        ]
        let resolver = Resolver.default
        for sample in samples {
            let resolvedTag = resolver.resolveTag(of: Node(sample.string))
            XCTAssertEqual(resolvedTag, sample.tag, "Resolver resolves unexpected tag", line: sample.line)
            let yaml = try RapidYAML.dump(object: sample.string)
            XCTAssertEqual(yaml, "\(sample.expected)\n", line: sample.line)
        }
    }
}

extension EmitterTests {
    static var allTests: [(String, (EmitterTests) -> () throws -> Void)] {
        return [
            ("testScalar", testScalar),
            ("testSequence", testSequence),
            ("testMapping", testMapping),
            ("testLineBreaks", testLineBreaks),
            ("testAllowUnicode", testAllowUnicode),
            ("testSortKeys", testSortKeys),
            ("testSmartQuotedString", testSmartQuotedString)
        ]
    }
}
