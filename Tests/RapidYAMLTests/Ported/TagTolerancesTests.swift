//
//  TagTolerancesTests.swift
//  RapidYAMLTests
//
//  Ported from Yams' test suite.
//

import XCTest
@testable import RapidYAML

class TagTolerancesTests: XCTestCase {

    struct Example: Codable, Hashable {
        var myCustomTagDeclaration: Tag
        var extraneousValue: Int
    }

    /// Any type that is Encodable and contains an `Tag`value but with a coding key different from
    /// YAMLTagProviding will not encode to a yaml tag
    /// This may be unexpected
    func testTagEncoding_undeclaredBehavior() throws {
        let expectedYAML = """
                           myCustomTagDeclaration: I-did-it-myyyyy-way
                           extraneousValue: 3

                           """

        let value = Example(myCustomTagDeclaration: "I-did-it-myyyyy-way",
                            extraneousValue: 3)

        let encoder = YAMLEncoder()
        let producedYAML = try encoder.encode(value)
        XCTAssertEqual(producedYAML, expectedYAML, "Produced YAML not identical to expected YAML.")
    }

    /// Any type that is Encodable and contains an `Tag`value with the same coding key as
    /// YAMLTagProviding will encode to a yaml tag even though the type does not conform to
    /// YAMLTagProviding
    /// This may be unexpected
    func testTagEncoding_undeclaredBehavior_7() throws {
        struct Example: Codable, Hashable {
            var yamlTag: Tag
            var extraneousValue: Int
        }
        let expectedYAML = """
                           !<I-did-it-myyyyy-way>
                           extraneousValue: 3

                           """

        let value = Example(yamlTag: "I-did-it-myyyyy-way",
                            extraneousValue: 3)

        let encoder = YAMLEncoder()
        let producedYAML = try encoder.encode(value)
        XCTAssertEqual(producedYAML, expectedYAML, "Produced YAML not identical to expected YAML.")
    }

    /// Tags are oddly permissive, but some characters do get escaped
    /// This may be unexpected
    func testTagEncoding_undeclaredBehavior_4() throws {
        struct Example: Codable, Hashable, YAMLTagProviding {
            var yamlTag: Tag?
            var extraneousValue: Int
        }

        // libYAML percent-encodes characters that are not safe in a verbatim tag — `|` becomes
        // `%7C` and `!` becomes `%21`. rapidyaml writes the name through unchanged.
        let expectedYAML = """
                           !<I-did-it-[]-*-|-!-()way>
                           extraneousValue: 3

                           """

        let value = Example(yamlTag: "I-did-it-[]-*-|-!-()way",
                            extraneousValue: 3)

        let encoder = YAMLEncoder()
        let producedYAML = try encoder.encode(value)
        XCTAssertEqual(producedYAML, expectedYAML, "Produced YAML not identical to expected YAML.")
    }

    /// Any type that is Decodable and contains an `Tag` value but with a coding key different from
    /// YAMLTagProviding will not decode an tag from the text representation.
    /// In this case a key not found error will be thrown during decoding
    /// This may be unexpected
    func testTagDecoding_undeclaredBehavior_1() throws {
        let sourceYAML = """
                           !<a-different-tag>
                           extraneousValue: 3

                           """
        let decoder = YAMLDecoder()
        XCTAssertThrowsError(try decoder.decode(Example.self, from: sourceYAML))
        // error is ^^ key not found, "myCustomTagDeclaration"
    }

    /// Any type that is Decodable and contains an `Tag` value but with a coding key different from
    /// YAMLTagProviding will not decode an tag from the text representation.
    /// This may be unexpected
    func testTagDecoding_undeclaredBehavior_6() throws {
        struct Example: Codable, Hashable {
            var myCustomTagDeclaration: Tag?
            var extraneousValue: Int
        }
        let sourceYAML = """
                           !<a-different-tag>
                           extraneousValue: 3

                           """

        let expectedValue = Example(myCustomTagDeclaration: nil,
                                    extraneousValue: 3)

        let decoder = YAMLDecoder()
        let decodedValue = try decoder.decode(Example.self, from: sourceYAML)
        XCTAssertEqual(decodedValue, expectedValue, "\(Example.self) did not round-trip to an equal value.")
    }

    /// Any type that is Decodable and contains an `Tag` value with the same coding key as YAMLTagProviding
    /// will decode an tag from the text representatio even though the type does not conform to YAMLTagCoding.
    /// This may be unexpected
    func testTagDecoding_undeclaredBehavior_8() throws {
        struct Example: Codable, Hashable {
            var yamlTag: Tag?
            var extraneousValue: Int
        }
        let sourceYAML = """
                           !<a-different-tag>
                           extraneousValue: 3

                           """

        let expectedValue = Example(yamlTag: "a-different-tag",
                                    extraneousValue: 3)

        let decoder = YAMLDecoder()
        let decodedValue = try decoder.decode(Example.self, from: sourceYAML)
        XCTAssertEqual(decodedValue, expectedValue, "\(Example.self) did not round-trip to an equal value.")
    }

    /// Any type that is Decodable and contains an `Tag` value but with a coding key different from YAMLTagProviding
    /// will not decode an tag from the text representation.
    /// This is expected behavior, but in a strange situation.
    func testTagDecoding_undeclaredBehavior_3() throws {
        let sourceYAML = """
                           !<a-different-tag>
                           extraneousValue: 3
                           myCustomTagDeclaration: deliver-us-from-evil

                           """
        let expectedValue = Example(myCustomTagDeclaration: "deliver-us-from-evil",
                                    extraneousValue: 3)

        let decoder = YAMLDecoder()
        let decodedValue = try decoder.decode(Example.self, from: sourceYAML)
        XCTAssertEqual(decodedValue, expectedValue, "\(Example.self) did not round-trip to an equal value.")

    }

    /// Any type that is Decodable and contains an `Tag` value but with a coding key different from YAMLTagProviding
    /// will not decode an tag from the text representation.
    /// This is expected behavior, but in a strange situation.
    func testTagDecoding_undeclaredBehavior_2() throws {
        let sourceYAML = """
                           !<a-different-tag>
                           extraneousValue: 3
                           myCustomTagDeclaration: "deliver us from |()evil"

                           """

        let expectedValue = Example(myCustomTagDeclaration: "deliver us from |()evil",
                                    extraneousValue: 3)

        let decoder = YAMLDecoder()
        let decodedValue = try decoder.decode(Example.self, from: sourceYAML)
        XCTAssertEqual(decodedValue, expectedValue, "\(Example.self) did not round-trip to an equal value.")

    }

}
