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

@Test func decodesAnEmptyValueAsNil() async throws {
    struct Optional: Decodable {
        var id: Int
        var name: String?
    }

    let decoded = try YAMLDecoder().decode(Optional.self, from: "id: 501\nname:\n")
    #expect(decoded.id == 501)
    #expect(decoded.name == nil)
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
