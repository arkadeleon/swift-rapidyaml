//
//  ResolverTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

@Suite struct ResolverTests {

    // MARK: Default rules

    @Test(arguments: [
        // bool
        ("true", RapidYAML.Tag.Name.bool), ("True", .bool), ("TRUE", .bool),
        ("false", .bool), ("False", .bool), ("FALSE", .bool),
        ("yes", .bool), ("Yes", .bool), ("YES", .bool),
        ("no", .bool), ("No", .bool), ("NO", .bool),
        ("on", .bool), ("On", .bool), ("ON", .bool),
        ("off", .bool), ("Off", .bool), ("OFF", .bool),
        // int
        ("0", .int), ("42", .int), ("-17", .int), ("+17", .int),
        ("1_000", .int), ("0b1010", .int), ("0o17", .int), ("017", .int), ("0x1F", .int),
        ("1:30", .int),
        // float
        ("1.5", .float), ("-1.5", .float), ("1e3", .float), ("1.2e-3", .float), (".5", .float),
        (".inf", .float), ("-.inf", .float), (".nan", .float), (".NaN", .float),
        ("1:30.5", .float),
        // null
        ("", .null), ("~", .null), ("null", .null), ("Null", .null), ("NULL", .null),
        // merge and value
        ("<<", .merge), ("=", .value),
        // timestamp
        ("2026-08-03", .timestamp), ("2026-08-03T11:22:33Z", .timestamp),
        ("2026-8-3 11:22:33.5 +9", .timestamp),
        // everything else
        ("hello", .str), ("nil", .str), ("TrUe", .str), ("0x", .str), ("1.2.3", .str),
        ("2026-13", .str), ("None", .str),
    ])
    func defaultResolverRecognises(string: String, tagName: RapidYAML.Tag.Name) {
        #expect(Resolver.default.resolveTag(from: string) == tagName)
    }

    @Test func basicResolverHasNoRules() {
        #expect(Resolver.basic.rules.isEmpty)
        #expect(Resolver.basic.resolveTag(from: "true") == .str)
        #expect(Resolver.basic.resolveTag(from: "") == .str)
    }

    @Test func defaultResolverRulesAreInPrecedenceOrder() {
        #expect(Resolver.default.rules.map(\.tag) == [.bool, .int, .float, .merge, .null, .timestamp, .value])
    }

    // MARK: Resolving nodes

    @Test func resolvesTagsOfNodes() {
        #expect(Resolver.default.resolveTag(of: Node("1")) == .int)
        #expect(Resolver.default.resolveTag(of: Node([Node("1")])) == .seq)
        #expect(Resolver.default.resolveTag(of: Node([(Node("a"), Node("1"))])) == .map)
        #expect(Resolver.default.resolveTag(of: .alias(.init("x"))) == .implicit)
    }

    // MARK: Customising

    @Test func appendingARule() throws {
        let resolver = try Resolver.default.appending(RapidYAML.Tag.Name(rawValue: "!phone"), "^[0-9]{3}-[0-9]{4}$")

        #expect(resolver.resolveTag(from: "555-1234") == RapidYAML.Tag.Name(rawValue: "!phone"))
        #expect(resolver.resolveTag(from: "42") == .int, "existing rules still apply")
        #expect(resolver.rules.count == Resolver.default.rules.count + 1)
    }

    @Test func appendedRulesRunAfterTheDefaults() throws {
        // `42` matches the int rule first, so a later rule never sees it.
        let resolver = try Resolver.default.appending(.str, "^[0-9]+$")
        #expect(resolver.resolveTag(from: "42") == .int)
    }

    @Test func replacingARule() throws {
        let resolver = try Resolver.default.replacing(.bool, with: "^(?:true|false)$")

        #expect(resolver.resolveTag(from: "true") == .bool)
        #expect(resolver.resolveTag(from: "yes") == .str, "no longer a bool")
        #expect(resolver.rules.count == Resolver.default.rules.count)
    }

    @Test func removingARule() {
        let resolver = Resolver.default.removing(.bool)

        #expect(resolver.resolveTag(from: "true") == .str)
        #expect(resolver.resolveTag(from: "42") == .int)
        #expect(resolver.rules.map(\.tag).contains(.bool) == false)
    }

    @Test func customisingLeavesTheDefaultResolverAlone() throws {
        _ = Resolver.default.removing(.bool)
        _ = try Resolver.default.appending(.str, "^.*$")

        #expect(Resolver.default.resolveTag(from: "true") == .bool)
        #expect(Resolver.default.rules.count == 7)
    }

    @Test func rulesExposeTheirPattern() {
        let bool = try! Resolver.Rule(.bool, "^(?:true|false)$")
        #expect(bool.pattern == "^(?:true|false)$")
        #expect(bool.tag == .bool)
    }

    @Test func anInvalidPatternThrows() {
        #expect(throws: (any Error).self) {
            try Resolver.Rule(.str, "([")
        }
    }

    // MARK: Composition

    @Test func composedScalarsCarryResolvedTags() throws {
        let node = try #require(try RapidYAML.compose(yaml: """
            int: 42
            float: 1.5
            bool: yes
            null:
            str: hello
            quoted: '42'
            tagged: !!str 42
            """))

        #expect(node["int"]?.tag.name == .int)
        #expect(node["float"]?.tag.name == .float)
        #expect(node["bool"]?.tag.name == .bool)
        #expect(node["null"]?.tag.name == .null)
        #expect(node["str"]?.tag.name == .str)
        #expect(node["tagged"]?.tag.name == .str, "an explicit tag wins over resolution")

        // A quoted scalar carries YAML's non-specific tag, so it is never resolved by value.
        #expect(node["quoted"]?.tag.name == .str)
    }

    @Test func composedMergeKeysAreTagged() throws {
        // Phase 5 acts on this; for now it only has to be recognised.
        let node = try #require(try RapidYAML.compose(yaml: "base: &b {a: 1}\nchild:\n  <<: *b\n"))
        let child = try #require(node["child"]?.mapping)
        #expect(child.keys.first?.tag.name == .merge)
    }

    @Test func resolutionMakesScalarsOfDifferentTypesUnequal() throws {
        // Both are the text `1`, but one is tagged a string.
        let node = try #require(try RapidYAML.compose(yaml: "a: 1\nb: !!str 1\n"))
        #expect(node["a"] != node["b"])
    }
}
