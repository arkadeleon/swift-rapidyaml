//
//  MarkTests.swift
//  RapidYAMLTests
//
//  Ported from Yams' test suite.
//

import XCTest
@testable import RapidYAML

final class MarkTests: XCTestCase, @unchecked Sendable {
    func testLocatableDeprecationMessageForSwiftLint() throws {
        let deprecatedRulesIdentifiers = [("variable_name", "identifier_name")].map { (Node($0.0), $0.1) }
        func deprecatedMessage(from rule: Node) -> String? {
            guard let index = deprecatedRulesIdentifiers.firstIndex(where: { $0.0 == rule }) else {
                return nil
            }
            let changed = deprecatedRulesIdentifiers[index].1
            return "\(rule.mark?.description ?? ""): warning: '\(rule.string ?? "")' has been renamed to " +
                "'\(changed)' and will be completely removed in a future release."
        }

        let yaml = """
            disabled_rules:
              - variable_name
              - line_length
            variable_name:
              min_length: 2
            """
        let configuration = try RapidYAML.compose(yaml: yaml)
        let disabledRules = configuration?.mapping?["disabled_rules"]?.array() ?? []
        let configuredRules = configuration?.mapping?.keys.filter({ $0 != "disabled_rules" }) ?? []
        let deprecatedMessages = (disabledRules + configuredRules).compactMap(deprecatedMessage(from:))
        XCTAssertEqual(deprecatedMessages, [
            "2:5: warning: 'variable_name' has been renamed to " +
                "'identifier_name' and will be completely removed in a future release.",
            "4:1: warning: 'variable_name' has been renamed to " +
                "'identifier_name' and will be completely removed in a future release."
            ])
    }

    func testMappingMarkIsCorrect() throws {
        let yaml = """
            values:
              sequence:
                - Hello
                - World
            """
        let root = try RapidYAML.compose(yaml: yaml)
        let values = root?.mapping?["values"]
        let sequence = values?.mapping?["sequence"]
        let firstElement = sequence?.sequence?[0]

        XCTAssertEqual(root?.mark?.description, "1:1")
        XCTAssertEqual(values?.mark?.description, "2:3")
        // A container has no scalar of its own to point at, so it reports the position of its
        // first child — `Hello` at 3:7 — rather than the `-` at 3:5.
        XCTAssertEqual(sequence?.mark?.description, "3:7")
        XCTAssertEqual(firstElement?.mark?.description, "3:7")
    }
}

extension MarkTests {
    static var allTests: [(String, (MarkTests) -> () throws -> Void)] {
        return [
            ("testLocatableDeprecationMessageForSwiftLint", testLocatableDeprecationMessageForSwiftLint),
            ("testMappingMarkIsCorrect", testMappingMarkIsCorrect)
        ]
    }
}
