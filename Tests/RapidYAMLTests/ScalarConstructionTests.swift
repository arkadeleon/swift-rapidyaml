//
//  ScalarConstructionTests.swift
//  RapidYAMLTests
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
import Testing
@testable import RapidYAML

@Suite struct ScalarConstructionTests {

    /// The `v` value of a one-key document, which is how most of these cases are written.
    private func value(_ yaml: String) throws -> Node {
        let node = try RapidYAML.compose(yaml: yaml)
        let root = try #require(node)
        return try #require(root["v"])
    }

    // MARK: Bool

    @Test(arguments: [
        ("true", true), ("True", true), ("TRUE", true),
        ("yes", true), ("Yes", true), ("YES", true),
        ("on", true), ("On", true), ("ON", true),
        ("false", false), ("False", false), ("FALSE", false),
        ("no", false), ("No", false), ("NO", false),
        ("off", false), ("Off", false), ("OFF", false),
    ])
    func constructsBools(string: String, expected: Bool) throws {
        #expect(try value("v: \(string)").bool == expected)
    }

    @Test func quotedBoolsAreStrings() throws {
        // A quoted scalar carries YAML's non-specific tag, so it is never resolved by value.
        #expect(try value("v: 'true'").bool == nil)
        #expect(try value("v: 'true'").string == "true")
        #expect(try value("v: \"yes\"").bool == nil)
    }

    // MARK: Int

    @Test(arguments: [
        ("42", 42), ("-17", -17), ("+17", 17), ("0", 0),
        ("0x1F", 31), ("-0x1F", -31), ("0o17", 15), ("017", 15), ("0b1010", 10),
        ("1_000_000", 1_000_000),
        // sexagesimal — base 60, as YAML 1.1 allows
        ("1:30", 90), ("-1:30", -90), ("190:20:30", 685_230),
    ])
    func constructsInts(string: String, expected: Int) throws {
        #expect(try value("v: \(string)").int == expected)
    }

    @Test func quotedIntsAreNotConstructed() throws {
        #expect(try value("v: '42'").int == nil)
    }

    @Test func unsignedIntegersRejectNegatives() {
        #expect(UInt.construct(from: Node.Scalar("-1", .implicit, .plain)) == nil)
        #expect(UInt.construct(from: Node.Scalar("1", .implicit, .plain)) == 1)
    }

    @Test func narrowIntegersRejectOverflow() {
        #expect(Int8.construct(from: Node.Scalar("127", .implicit, .plain)) == 127)
        #expect(Int8.construct(from: Node.Scalar("128", .implicit, .plain)) == nil)
        #expect(UInt8.construct(from: Node.Scalar("255", .implicit, .plain)) == 255)
        #expect(UInt8.construct(from: Node.Scalar("256", .implicit, .plain)) == nil)
    }

    // MARK: Double

    @Test(arguments: [
        ("1.5", 1.5), ("-1.5", -1.5), ("1e3", 1000.0), ("1.2e-3", 0.0012), (".5", 0.5),
        ("1_000.5", 1000.5), ("1:30.5", 90.5),
    ])
    func constructsDoubles(string: String, expected: Double) throws {
        #expect(try value("v: \(string)").float == expected)
    }

    @Test func constructsInfinitiesAndNaN() throws {
        #expect(try value("v: .inf").float == .infinity)
        #expect(try value("v: +.inf").float == .infinity)
        #expect(try value("v: -.inf").float == -.infinity)
        #expect(try value("v: .nan").float?.isNaN == true)
        #expect(try value("v: .NaN").float?.isNaN == true)
    }

    // MARK: Null

    @Test(arguments: ["", " ~", " null", " Null", " NULL"])
    func constructsNull(string: String) throws {
        #expect(try value("v:\(string)").null == NSNull())
    }

    @Test func quotedNullIsAString() throws {
        #expect(try value("v: 'null'").null == nil)
        #expect(try value("v: ''").null == nil)
    }

    // MARK: Data

    @Test func constructsBinary() throws {
        let node = try value("v: !!binary aGVsbG8=")
        #expect(node.binary.flatMap { String(data: $0, encoding: .utf8) } == "hello")
        #expect(node.any is Data)
    }

    // MARK: Date

    @Test func constructsTimestamps() throws {
        let expected = DateComponents(calendar: Calendar(identifier: .gregorian),
                                      timeZone: TimeZone(secondsFromGMT: 0),
                                      year: 2026, month: 8, day: 3, hour: 11, minute: 22, second: 33).date

        #expect(try value("v: 2026-08-03T11:22:33Z").timestamp == expected)
        #expect(try value("v: 2026-08-03 11:22:33 +0").timestamp == expected)
        #expect(try value("v: 2026-8-3t11:22:33Z").timestamp == expected)
    }

    @Test func timestampOffsetsAreApplied() throws {
        let utc = try value("v: 2026-08-03T11:22:33Z").timestamp
        #expect(try value("v: 2026-08-03T06:22:33 -5").timestamp == utc)
        #expect(try value("v: 2026-08-03T20:52:33 +9:30").timestamp == utc)
    }

    @Test func timestampFractionsAreApplied() throws {
        let whole = try #require(value("v: 2026-08-03T11:22:33Z").timestamp)
        let fraction = try #require(value("v: 2026-08-03T11:22:33.25Z").timestamp)
        #expect(fraction.timeIntervalSince(whole) == 0.25)
    }

    @Test func constructsDateOnlyTimestamps() throws {
        let expected = DateComponents(calendar: Calendar(identifier: .gregorian),
                                      timeZone: TimeZone(secondsFromGMT: 0),
                                      year: 2026, month: 8, day: 3).date
        #expect(try value("v: 2026-08-03").timestamp == expected)
    }

    // MARK: UUID, Decimal, URL

    @Test func constructsUUIDDecimalAndURL() throws {
        let uuid = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        #expect(try value("v: \(uuid)").uuid == UUID(uuidString: uuid))

        let scalar = Node.Scalar("1.25", .implicit, .plain)
        #expect(Decimal.construct(from: scalar) == Decimal(string: "1.25"))
        #expect(URL.construct(from: Node.Scalar("https://example.com", .implicit, .plain))
            == URL(string: "https://example.com"))
    }

    // MARK: any

    @Test func anyConstructsWholeTrees() throws {
        let composed = try RapidYAML.compose(yaml: "a: 1\nb: [x, 2.5]\nc: {d: true}\n")
        let node = try #require(composed)
        let any = try #require(node.any as? [AnyHashable: Any])

        #expect(any["a"] as? Int == 1)
        #expect((any["b"] as? [Any])?.first as? String == "x")
        #expect((any["b"] as? [Any])?.last as? Double == 2.5)
        #expect((any["c"] as? [AnyHashable: Any])?["d"] as? Bool == true)
    }

    @Test func anyFlattensMergeKeys() throws {
        let node = try value("base: &b {a: 1, b: 2}\nv: {<<: *b, c: 3}\n")
        let any = try #require(node.any as? [AnyHashable: Any])

        #expect(any.count == 3)
        #expect(any["a"] as? Int == 1)
        #expect(any["c"] as? Int == 3)
    }

    @Test func anyFlattensASequenceOfMergeKeys() throws {
        let node = try value("""
            one: &x {a: 1, b: 2}
            two: &y {b: 20, c: 3}
            v: {<<: [*x, *y], d: 4}
            """)
        let any = try #require(node.any as? [AnyHashable: Any])

        #expect(any.count == 4)
        // The earlier mapping in the sequence wins.
        #expect(any["b"] as? Int == 2)
        #expect(any["c"] as? Int == 3)
    }

    @Test func anyConstructsSetsOmapsAndPairs() throws {
        let setAny = try value("v: !!set {a, b, c}").any
        let set = try #require(setAny as? Set<AnyHashable>)
        #expect(set == ["a", "b", "c"])

        let omapAny = try value("v: !!omap [{a: 1}, {b: 2}]").any
        let omap = try #require(omapAny as? [(Any, Any)])
        #expect(omap.map { $0.0 as? String } == ["a", "b"])
        #expect(omap.map { $0.1 as? Int } == [1, 2])

        // Unlike an omap, pairs allow a repeated key.
        let pairsAny = try value("v: !!pairs [{a: 1}, {a: 2}]").any
        let pairs = try #require(pairsAny as? [(Any, Any)])
        #expect(pairs.map { $0.0 as? String } == ["a", "a"])
    }

    @Test func anyResolvesTheValueKey() throws {
        // `=` names a mapping's default value.
        let node = try value("v: {=: fallback, other: 1}")
        #expect(node.string == "fallback")
    }

    @Test func nsMutableMapsProduceReferenceTypes() throws {
        let constructor = Constructor(Constructor.defaultScalarMap,
                                      Constructor.nsMutableMappingMap,
                                      Constructor.nsMutableSequenceMap)
        let composed = try RapidYAML.compose(yaml: "a: 1\nb: [x]\n", .default, constructor)
        let node = try #require(composed)

        let any = try #require(node.any as? NSMutableDictionary)
        #expect(any["a"] as? Int == 1)
        #expect(any["b"] is NSMutableArray)
    }

    // MARK: array(of:)

    @Test func typedArrays() throws {
        let node = try value("v: [1, 2, 3]")
        #expect(node.array(of: Int.self) == [1, 2, 3])
        #expect(node.array(of: String.self) == ["1", "2", "3"])

        // Elements that will not construct are dropped.
        #expect(try value("v: [1, x, 3]").array(of: Int.self) == [1, 3])
        #expect(try value("v: not a sequence").array(of: Int.self) == [])
    }

    // MARK: Customising

    @Test func aCustomScalarMapOverridesTheDefault() throws {
        var scalarMap = Constructor.defaultScalarMap
        scalarMap[.int] = { scalar in Int(scalar.string).map { $0 * 2 } }
        let constructor = Constructor(scalarMap)

        let composed = try RapidYAML.compose(yaml: "v: 21\n", .default, constructor)
        let node = try #require(composed)
        #expect(node["v"]?.any as? Int == 42)
    }

    // MARK: Sexagesimal

    @Test func sexagesimalRejectsMalformedComponents() {
        #expect(Int.construct(from: Node.Scalar("1:x", .implicit, .plain)) == nil)
        #expect(Double.construct(from: Node.Scalar("1:x", .implicit, .plain)) == nil)
    }
}
