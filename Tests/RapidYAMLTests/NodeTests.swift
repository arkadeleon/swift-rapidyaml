//
//  NodeTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

@Suite struct NodeModelTests {

    @Test func scalarEqualityIgnoresStyleAndMark() {
        let plain = Node.Scalar("a", .implicit, .plain, Mark(line: 1, column: 1))
        let quoted = Node.Scalar("a", .implicit, .doubleQuoted, Mark(line: 9, column: 9))
        #expect(plain == quoted)
        #expect(Node.scalar(plain).hashValue == Node.scalar(quoted).hashValue)
    }

    @Test func scalarEqualityDistinguishesResolvedTags() {
        #expect(Node("a", Tag(.str)) == Node("a", Tag(.implicit)))
        #expect(Node("a", Tag(.int)) != Node("a", Tag(.str)))
    }

    @Test func settingStringResetsTheTag() {
        var scalar = Node.Scalar("1", Tag(.int))
        #expect(scalar.tag.name == .int)
        scalar.string = "2"
        #expect(scalar.tag.name == .implicit)
    }

    @Test func literalsBuildNodes() {
        let sequence: Node = [1, 2, 3]
        #expect(sequence.sequence?.count == 3)
        #expect(sequence.sequence?.first == Node("1", Tag(.int)))

        let mapping: Node = ["a": 1, "b": 2]
        #expect(mapping.mapping?.count == 2)
        #expect(mapping["a"] == Node("1", Tag(.int)))

        let scalar: Node = "hello"
        #expect(scalar.string == "hello")
        #expect(scalar.tag.name == .str)

        let float: Node = 1.5
        #expect(float.tag.name == .float)
    }

    @Test func mappingPreservesInsertionOrder() {
        var mapping = Node.Mapping([("b", "1"), ("a", "2")])
        mapping["c"] = "3"

        #expect(mapping.keys.map { $0.string } == ["b", "a", "c"])
        #expect(mapping.values.map { $0.string } == ["1", "2", "3"])
        #expect(mapping.index(forKey: "a") == 1)

        mapping["a"] = "9"
        #expect(mapping.keys.map { $0.string } == ["b", "a", "c"], "updating a key keeps its position")
        #expect(mapping["a"]?.string == "9")

        mapping["b"] = nil
        #expect(mapping.keys.map { $0.string } == ["a", "c"])
    }

    @Test func sequenceIsARangeReplaceableCollection() {
        var sequence: Node.Sequence = ["a", "b", "c"]
        sequence.replaceSubrange(1..<2, with: ["x", "y"])
        #expect(sequence.map { $0.string } == ["a", "x", "y", "c"])

        sequence.append("z")
        #expect(sequence.last?.string == "z")
        #expect(sequence.count == 5)
    }

    @Test func subscriptsReadThroughContainers() {
        let node: Node = ["a": ["x": "1"], "b": ["p", "q"]]

        #expect(node["a"]?["x"]?.string == "1")
        #expect(node["b"]?[Node("1", Tag(.int))]?.string == "q")
        #expect(node["missing"] == nil)
        #expect(Node("scalar")["anything"] == nil, "subscripting a scalar is a no-op")
    }

    @Test func subscriptsWriteThroughContainers() {
        var node: Node = ["a": "1"]
        node["b"] = "2"
        #expect(node.mapping?.keys.map { $0.string } == ["a", "b"])

        var scalar = Node("scalar")
        scalar["a"] = "1"
        #expect(scalar == Node("scalar"), "subscripting a scalar is a no-op")
    }

    @Test func nodesAreComparable() {
        #expect(Node("a") < Node("b"))
        #expect(!(Node("b") < Node("a")))
        #expect(!(Node("a") < Node([Node("a")])), "unlike kinds are never ordered")
    }

    @Test func aliasComparesByAnchor() {
        #expect(Node.Alias("a") == Node.Alias("a", Tag(.str), Mark(line: 2, column: 2)))
        #expect(Node.Alias("a") < Node.Alias("b"))
    }

    @Test func implicitTagsAreResolvedFromContents() {
        #expect(Node("1").tag.name == .int)
        #expect(Node([Node("1")]).tag.name == .seq)
        #expect(Node([(Node("a"), Node("1"))]).tag.name == .map)
        #expect(Node("1", Tag(.int)).tag.name == .int, "an explicit tag is left alone")
    }

    @Test func nonSpecificTagsResolveToTheFailsafeSchema() {
        // `!` means "do not resolve me by value".
        #expect(Node("1", Tag(.nonSpecific)).tag.name == .str)
        #expect(Node([Node("1")], Tag(.nonSpecific)).tag.name == .seq)
    }

    @Test func aResolverWithoutRulesLeavesEverythingAString() {
        #expect(Node("1", Tag(.implicit, .basic)).tag.name == .str)
        #expect(Node("true", Tag(.implicit, .basic)).tag.name == .str)
    }
}

@Suite struct ComposerTests {

    private func compose(_ yaml: String) throws -> Node {
        let node = try RapidYAML.compose(yaml: yaml)
        return try #require(node)
    }

    @Test func composesScalarsMappingsAndSequences() throws {
        let node = try compose("a: 1\nb:\n  - x\n  - y\n")

        #expect(node.mapping?.count == 2)
        #expect(node["a"]?.string == "1")
        #expect(node["b"]?.array().map { $0.string } == ["x", "y"])
    }

    @Test func preservesKeyOrder() throws {
        // The old Objective-C bridge built mappings into an NSMutableDictionary, which made this
        // order non-deterministic.
        let node = try compose("{delta: 1, alpha: 2, charlie: 3, bravo: 4}")
        #expect(node.mapping?.keys.map { $0.string } == ["delta", "alpha", "charlie", "bravo"])
    }

    @Test func emptySourceComposesToNothing() throws {
        let node = try RapidYAML.compose(yaml: "")
        #expect(node == nil)
    }

    @Test func composeRejectsAStreamOfSeveralDocuments() throws {
        // `compose_all` is how you read the whole stream.
        let error = #expect(throws: YAMLError.self) {
            try RapidYAML.compose(yaml: "---\na: 1\n---\nb: 2\n")
        }

        guard case .composer(let context, let problem, _, _) = try #require(error) else {
            Issue.record("expected a composer error, got \(String(describing: error))")
            return
        }
        #expect(context?.text == "expected a single document in the stream")
        #expect(problem == "but found another document")
    }

    @Test func emptyValueComposesToAnEmptyScalar() throws {
        let node = try compose("key:\n")
        #expect(node["key"] == Node(""))
    }

    // MARK: Anchors and aliases

    @Test func aliasesResolveToTheAnchoredNode() throws {
        let node = try compose("a: &x 1\nb: *x\n")

        #expect(node["b"]?.string == "1")
        #expect(node["a"]?.anchor?.rawValue == "x")
        #expect(node["b"]?.anchor?.rawValue == "x", "the alias yields the anchored node itself")
    }

    @Test func aliasesResolveToAnchoredContainers() throws {
        let node = try compose("a: &x {p: 1}\nb: *x\n")
        #expect(node["b"]?["p"]?.string == "1")
        #expect(node["a"] == node["b"])
    }

    @Test func undefinedAliasIsAComposerError() throws {
        let error = #expect(throws: YAMLError.self) {
            try RapidYAML.compose(yaml: "a: *missing\n")
        }

        guard case .composer(_, let problem, let mark, _) = try #require(error) else {
            Issue.record("expected a composer error, got \(String(describing: error))")
            return
        }
        #expect(problem == "found undefined alias")
        #expect(mark.line == 1)
        #expect(mark.column == 4)

        // Byte-for-byte what Yams reports for the same source.
        #expect(error?.description == """
            1:4: error: composer: found undefined alias:
            a: *missing
               ^
            """)
    }

    @Test func duplicateKeysAreRejected() throws {
        let error = #expect(throws: YAMLError.self) {
            try RapidYAML.compose(yaml: "a: 1\nb: 2\na: 3\n")
        }

        guard case .duplicatedKeysInMapping(let duplicates, _) = try #require(error) else {
            Issue.record("expected a duplicate key error, got \(String(describing: error))")
            return
        }
        #expect(duplicates == ["a"])
    }

    // MARK: Tags

    @Test func tagsAreNormalisedToTheirLongForm() throws {
        let node = try compose("a: !!int 5\nb: !<tag:yaml.org,2002:bool> true\nc: !custom 7\n")

        #expect(node["a"]?.tag.name == .int)
        #expect(node["b"]?.tag.name == .bool)
        #expect(node["c"]?.tag.name == Tag.Name(rawValue: "!custom"), "non-schema tags pass through")
    }

    // MARK: Styles

    @Test func scalarStylesAreCarriedThrough() throws {
        let node = try compose("a: plain\nb: 'sq'\nc: \"dq\"\nd: |\n  lit\ne: >\n  fold\n")

        #expect(node["a"]?.scalar?.style == .plain)
        #expect(node["b"]?.scalar?.style == .singleQuoted)
        #expect(node["c"]?.scalar?.style == .doubleQuoted)
        #expect(node["d"]?.scalar?.style == .literal)
        #expect(node["e"]?.scalar?.style == .folded)
    }

    @Test func collectionStylesAreCarriedThrough() throws {
        // Yams reports `.any` for every container — it reads the style off libYAML's *end* event,
        // which does not carry one. rapidyaml tells us the real style.
        #expect(try compose("{a: 1}").mapping?.style == .flow)
        #expect(try compose("a: 1\n").mapping?.style == .block)
        #expect(try compose("[1]").sequence?.style == .flow)
        #expect(try compose("- 1\n").sequence?.style == .block)
    }

    // MARK: Marks

    @Test func plainScalarsAreMarkedWhereYamsMarksThem() throws {
        let node = try compose("a: 1\nb: two\n")

        #expect(node.mapping?[0].key.mark?.description == "1:1")
        #expect(node.mapping?[0].value.mark?.description == "1:4")
        #expect(node.mapping?[1].key.mark?.description == "2:1")
        #expect(node.mapping?[1].value.mark?.description == "2:4")
    }

    @Test func marksCountColumnsInUnicodeScalars() throws {
        // rapidyaml reports the value at byte column 11; `藥水` starts at scalar column 5.
        let node = try compose("紅色: 藥水\n")
        #expect(node.mapping?[0].value.mark?.description == "1:5")
    }
}
