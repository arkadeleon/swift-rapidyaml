//
//  NodeInternalHelpersTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import XCTest
@testable import RapidYAML

final class NodeInternalHelpersTests: XCTestCase, @unchecked Sendable {
    // swiftlint:disable force_try
    func testIsScalar() {
        var node = Node("1") // a scalar
        XCTAssertEqual(node.isScalar, true)
        node = try! Node(["key": "1"]) // a mapping
        XCTAssertEqual(node.isScalar, false)
        node = try! Node(["one", "1"]) // a sequnce
        XCTAssertEqual(node.isScalar, false)
    }
    // swiftlint:enable force_try
}

extension NodeInternalHelpersTests {
    static var allTests: [(String, (NodeInternalHelpersTests) -> () throws -> Void)] {
        return [
            ("testIsScalar", testIsScalar)
        ]
    }
}
