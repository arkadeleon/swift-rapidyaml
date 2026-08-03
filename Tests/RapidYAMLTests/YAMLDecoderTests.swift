//
//  YAMLDecoderTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2025/6/12.
//

import Foundation
import Testing
@testable import RapidYAML

private struct Item: Decodable {
    var id: Int
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

/// Malformed YAML used to abort the process inside rapidyaml's default error callbacks. The ported
/// suite covers a decoder rejecting the *shape* of a document; this is it rejecting the bytes.
@Test(arguments: [
    "Id: 501\n  Name: Red Potion\n",
    "Id: [501, 502\n",
    "\t- Id: 501\n",
])
func decoderThrowsOnMalformedYAML(yamlString: String) async throws {
    #expect(throws: DecodingError.self) {
        try YAMLDecoder().decode(Item.self, from: yamlString)
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

/// Every `YAMLError.description`, including the cases nothing produces here, diffed against what
/// Yams prints for the same value. The ported `YAMLErrorTests` can only reach the reachable ones.
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

/// `Decoder.mark` — the ported `MarkTests` only covers `Node.mark`.
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
