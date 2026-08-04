//
//  YAMLErrorTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import XCTest
@testable import RapidYAML

final class YAMLErrorTests: XCTestCase, @unchecked Sendable {
    /// Yams reports libYAML's "incompatible %YAML directive"; rapidyaml has no version directive
    /// at all, so the option is refused up front instead.
    func testYAMLErrorEmitter() throws {
        XCTAssertThrowsError(try RapidYAML.serialize(node: "test", version: (1, 3))) { error in
            XCTAssertTrue(error is YAMLError)
            XCTAssertEqual("\(error)", "version is not supported by the rapidyaml emitter")
        }
    }

    /// libYAML rejects a control character inside a quoted scalar, which is the only thing that
    /// produces a `.reader` error in Yams. rapidyaml accepts it, so `.reader` stays unreachable.
    func testYAMLErrorReader() throws {
        let yaml = "test: 'テスト\u{12}'"
        let node = try Parser(yaml: yaml).nextRoot()
        XCTAssertEqual(node?["test"]?.string, "テスト\u{12}")
    }

    func testYAMLErrorScanner() throws {
        let yaml = "test: 'テスト"
        XCTAssertThrowsError(_ = try Parser(yaml: yaml).nextRoot()) { error in
            XCTAssertTrue(error is YAMLError)
            // rapidyaml has no separate scanner stage, so this arrives as a parse error.
            XCTAssertEqual("\(error)", """
                2:1: error: parser: reached end of file while looking for closing quote:
                test: 'テスト
                ^
                """
            )
        }
    }

    func testYAMLErrorParser() throws {
        let yaml = "- [キー1: 値1]\n- [key1: value1, key2: ,"
        XCTAssertThrowsError(_ = try Parser(yaml: yaml).nextRoot()) { error in
            XCTAssertTrue(error is YAMLError)
            // rapidyaml carries no error context, and points at the unterminated bracket.
            XCTAssertEqual("\(error)", """
                2:25: error: parser: missing terminating ]:
                - [key1: value1, key2: ,
                                        ^
                """
            )
        }
    }

    /// libYAML reads `|` as an empty literal and then rejects `a` as a stray document; rapidyaml
    /// folds `a` into the literal block instead. Neither is wrong — the source is ambiguous — but
    /// it means there is no error to report here.
    func testNextRootThrowsOnInvalidYaml() throws {
        let parser = try Parser(yaml: "|\na")
        XCTAssertEqual(try parser.nextRoot(), Node("a\n", Tag(.str), .literal))
        XCTAssertNil(try parser.nextRoot())
    }

    func testSingleRootThrowsOnInvalidYaml() throws {
        let parser = try Parser(yaml: "|\na")
        XCTAssertEqual(try parser.singleRoot(), Node("a\n", Tag(.str), .literal))
    }

    func testSingleRootThrowsOnMultipleDocuments() throws {
        let multipleDocuments = "document 1\n---\ndocument 2\n"
        let parser = try Parser(yaml: multipleDocuments)
        XCTAssertThrowsError(try parser.singleRoot()) { error in
            XCTAssertTrue(error is YAMLError)
            // rapidyaml does not record the position of a `---` marker, so this points at the
            // next document's first scalar instead.
            XCTAssertEqual("\(error)", """
                3:1: error: composer: expected a single document in the stream in line 1, column 1
                but found another document:
                document 2
                ^
                """
            )
        }
    }

    func testUndefinedAliasCausesError() throws {
        let undefinedAlias = "*undefinedAlias\n"
        let parser = try Parser(yaml: undefinedAlias)
        XCTAssertThrowsError(try parser.singleRoot()) { error in
            XCTAssertTrue(error is YAMLError)
            XCTAssertEqual("\(error)", """
                1:1: error: composer: found undefined alias:
                *undefinedAlias
                ^
                """
            )
        }
    }

    func testScannerErrorMayHaveNullContext() throws {
        // https://github.com/realm/SwiftLint/issues/1436
        let swiftlint1436 = "large_tuple: warning: 3"
        // rapidyaml parses the whole stream up front, so this fails in the initializer rather
        // than in `singleRoot()`.
        XCTAssertThrowsError(try Parser(yaml: swiftlint1436)) { error in
            XCTAssertTrue(error is YAMLError)
            // A parse error rather than a scanner one, and without libYAML's context.
            XCTAssertEqual("\(error)", """
                1:23: error: parser: two colons on same line:
                large_tuple: warning: 3
                                      ^
                """
            )
        }
    }

    func testYAMLErrorDataCouldNotBeDecoded() {
        let yamlString = """
            emoji: 🙃
        """
        let utf16Data = yamlString.data(using: .utf16)!
        XCTAssertThrowsError(try Parser(yaml: utf16Data, encoding: .utf8)) { error in
            XCTAssertTrue(error is YAMLError)
            XCTAssertEqual("\(error)", """
                String could not be decoded from data using 'Unicode (UTF-8)' encoding
                """
            )
        }
    }

    func testDuplicateKeysCannotBeParsed() throws {
        let yamlString = """
                         a: value
                         a: different_value
                         """
        XCTAssertThrowsError(try Parser(yaml: yamlString).singleRoot()) { error in
            XCTAssertTrue(error is YAMLError)
            XCTAssertEqual("\(error)", """
                Parser: expected all keys to be unique but found the following duplicated key(s): 'a'.
                Context:
                a: value
                a: different_value in line 1, column 1

                """)
        }
    }

    func testDuplicatedKeysCannotBeParsed_MultipleDuplicates() throws {
        let yamlString = """
                         a: value
                         a: different_value
                         b: value
                         b: different_value
                         b: different_different_value
                         """
        XCTAssertThrowsError(try Parser(yaml: yamlString).singleRoot()) { error in
            XCTAssertTrue(error is YAMLError)
            XCTAssertEqual("\(error)", """
                Parser: expected all keys to be unique but found the following duplicated key(s): 'a', 'b'.
                Context:
                a: value
                a: different_value
                b: value
                b: different_value
                b: different_different_value in line 1, column 1

                """)
        }
    }
}

extension YAMLErrorTests {
    static var allTests: [(String, (YAMLErrorTests) -> () throws -> Void)] {
        return [
            ("testYAMLErrorReader", testYAMLErrorReader),
            ("testYAMLErrorScanner", testYAMLErrorScanner),
            ("testYAMLErrorParser", testYAMLErrorParser),
            ("testNextRootThrowsOnInvalidYaml", testNextRootThrowsOnInvalidYaml),
            ("testSingleRootThrowsOnInvalidYaml", testSingleRootThrowsOnInvalidYaml),
            ("testSingleRootThrowsOnMultipleDocuments", testSingleRootThrowsOnMultipleDocuments),
            ("testUndefinedAliasCausesError", testUndefinedAliasCausesError),
            ("testScannerErrorMayHaveNullContext", testScannerErrorMayHaveNullContext),
            ("testYAMLErrorDataCouldNotBeDecoded", testYAMLErrorDataCouldNotBeDecoded)
        ]
    }
}
