//
//  RapidYAMLTests.swift
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
    let decoder = YAMLDecoder()

    let error = #expect(throws: DecodingError.self) {
        try decoder.decode(Item.self, from: "Id: 501\nName: [Red Potion\n")
    }

    guard case .dataCorrupted(let context) = error else {
        Issue.record("expected a dataCorrupted error, got \(String(describing: error))")
        return
    }

    let underlyingError = try #require(context.underlyingError as? NSError)
    #expect(underlyingError.domain == "YAMLNodeErrorDomain")
    #expect(underlyingError.localizedDescription == "missing terminating ]")
    #expect(underlyingError.userInfo["YAMLNodeErrorLine"] as? Int == 3)
}
