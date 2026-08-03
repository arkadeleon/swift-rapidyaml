//
//  RapidYAMLLimitationTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

/// Valid YAML that rapidyaml refuses, where libyaml — and so Yams — accepts it.
///
/// These are pinned so that a rapidyaml upgrade which fixes one of them shows up as a failing
/// test rather than going unnoticed.
@Suite struct RapidYAMLLimitationTests {

    @Test func containersCannotBeUsedAsKeys() throws {
        // Yams composes this into a mapping keyed by a sequence.
        #expect(throws: YAMLError.self) {
            try RapidYAML.load(yaml: "? [a, b]\n: value\n")
        }
    }

    @Test func explicitKeyBlocksCannotBeFollowedBySiblings() throws {
        // A `? key` block on its own is fine...
        #expect(try RapidYAML.load(yaml: "a:\n  ? x\n") != nil)
        #expect(try RapidYAML.load(yaml: "a: !!set {x, y}\n") != nil)

        // ...but de-indenting back out to a sibling key is "invalid indentation".
        #expect(throws: YAMLError.self) {
            try RapidYAML.load(yaml: "a:\n  ? x\nb: 1\n")
        }
    }

    @Test func flowContainersMustNotCloseAtColumnZero() throws {
        // This is how embedded JSON is usually written, and it is a parse error.
        #expect(throws: YAMLError.self) {
            try RapidYAML.load(yaml: "json: {\n  \"a\": 1\n}\n")
        }
        #expect(throws: YAMLError.self) {
            try RapidYAML.load(yaml: "list: [\n  1\n]\n")
        }

        // A multi-line quoted scalar closes the same way.
        #expect(throws: YAMLError.self) {
            try RapidYAML.load(yaml: "a: \"one\ntwo\n\"\n")
        }

        // Indenting the closing bracket, or keeping it on one line, both work.
        #expect(try RapidYAML.load(yaml: "json: {\n  \"a\": 1\n  }\n") != nil)
        #expect(try RapidYAML.load(yaml: "json: {\"a\": 1}\n") != nil)
    }

    @Test func blockScalarsAlwaysEndWithANewline() throws {
        // libYAML's clip chomping keeps a trailing break only if the source had one; with no
        // final newline in the source there is none to keep. rapidyaml adds one regardless.
        #expect(try RapidYAML.load(yaml: "|\n a\n b") as? String == "a\nb\n")
        #expect(try RapidYAML.load(yaml: ">\n a\n b") as? String == "a b\n")

        // Explicit chomping indicators behave as the spec says.
        #expect(try RapidYAML.load(yaml: "|-\n a\n b") as? String == "a\nb")
        #expect(try RapidYAML.load(yaml: "|+\n a\n b\n\n") as? String == "a\nb\n\n")
    }
}
