//
//  Composer.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
internal import YAMLNode

/// Builds a `Node` tree out of a parsed rapidyaml tree.
///
/// This mirrors the composition half of Yams' `Parser`: aliases are dereferenced to the node
/// their anchor names, rather than surfacing as `Node.alias`, and duplicate mapping keys are
/// rejected.
///
/// Phase 6 puts the public `load` / `compose` API on top of this; for now it only serves the
/// decoder, and only the first document of a stream is reachable.
struct Composer {

    /// The YAML source, carried only so that a failure can report it.
    private let yaml: String

    /// The resolver every composed node's `Tag` is built with.
    private let resolver: Resolver

    /// The nodes named so far by an anchor. An alias can only refer to an anchor that has already
    /// been composed, which is what makes a recursive document impossible.
    private var anchors: [Anchor: Node] = [:]

    private init(yaml: String, resolver: Resolver) {
        self.yaml = yaml
        self.resolver = resolver
    }

    /// Parses `yamlString` and composes its first document.
    ///
    /// - parameter yamlString: The YAML source to parse.
    /// - parameter resolver:   The `Resolver` to resolve implicit tags with.
    ///
    /// - returns: The document's root node, or `nil` if the source holds no document.
    ///
    /// - throws: `YAMLError` if the source is not valid YAML, or cannot be composed.
    static func compose(yaml yamlString: String, resolver: Resolver = .default) throws -> Node? {
        let root: YAMLNode
        do {
            root = try YAMLNode(yamlString: yamlString)
        } catch {
            // The bridge reports failures as an NSError; YAMLError is what callers expect.
            throw YAMLError(from: error as NSError, with: yamlString)
        }

        var composer = Composer(yaml: yamlString, resolver: resolver)
        return try composer.document(root)
    }

    private mutating func document(_ node: YAMLNode) throws -> Node? {
        switch node.kind {
        case .stream:
            guard let first = node.children.first else { return nil }
            return try document(first)
        case .document, .unknown:
            // A document with no contents, or an empty source.
            return nil
        default:
            return try value(of: node)
        }
    }

    // MARK: - Composition

    /// Composes the node on the value side of `node` — the whole node, unless it is a child of a
    /// mapping, in which case this is the pair's value.
    private mutating func value(of node: YAMLNode) throws -> Node {
        let mark = mark(line: node.valueLine, column: node.valueColumn)

        if let alias = node.valueAlias {
            return try dereference(alias, at: mark)
        }

        let tag = tag(node.valueTag)
        let anchor = node.valueAnchor.map(Anchor.init(rawValue:))

        let composed: Node
        switch node.kind {
        case .mapping:
            var pairs: [(Node, Node)] = []
            pairs.reserveCapacity(node.children.count)
            for child in node.children {
                pairs.append((try key(of: child), try value(of: child)))
            }
            try checkDuplicates(in: pairs.map { $0.0 })
            composed = .mapping(.init(pairs, tag, mappingStyle(node.collectionStyle), mark, anchor))
        case .sequence:
            let nodes = try node.children.map { try value(of: $0) }
            composed = .sequence(.init(nodes, tag, sequenceStyle(node.collectionStyle), mark, anchor))
        default:
            // A value that was written but left empty — `key:` — has no scalar of its own.
            composed = .scalar(.init(node.value ?? "", tag, scalarStyle(node.valueStyle), mark, anchor))
        }

        register(anchor, for: composed)
        return composed
    }

    /// Composes the key side of a mapping's child.
    ///
    /// - note: rapidyaml stores a key as a scalar, so a complex key — `? [a, b]` — cannot be
    ///         represented. Yams supports those through libyaml's event stream.
    private mutating func key(of node: YAMLNode) throws -> Node {
        let mark = mark(line: node.keyLine, column: node.keyColumn)

        if let alias = node.keyAlias {
            return try dereference(alias, at: mark)
        }

        let anchor = node.keyAnchor.map(Anchor.init(rawValue:))
        let composed = Node.scalar(.init(node.key ?? "", tag(node.keyTag), scalarStyle(node.keyStyle), mark, anchor))

        register(anchor, for: composed)
        return composed
    }

    // MARK: - Anchors and aliases

    private mutating func register(_ anchor: Anchor?, for node: Node) {
        guard let anchor else { return }
        anchors[anchor] = node
    }

    private func dereference(_ name: String, at mark: Mark?) throws -> Node {
        guard let node = anchors[Anchor(rawValue: name)] else {
            throw YAMLError.composer(context: nil,
                                     problem: "found undefined alias",
                                     mark ?? Mark(line: 0, column: 0),
                                     yaml: yaml)
        }
        return node
    }

    // MARK: - Duplicate keys

    private func checkDuplicates(in keys: [Node]) throws {
        let duplicates: [Node: [Node]] = Dictionary(grouping: keys) { $0 }.filter { $1.count > 1 }
        guard duplicates.isEmpty else {
            let sortedKeys = duplicates.keys.sorted()
            let firstMark = sortedKeys.first?.mark ?? .init(line: 0, column: 0)
            let duplicates = sortedKeys.map { $0.string ?? "<uncovertable>" }
            throw YAMLError.duplicatedKeysInMapping(duplicates: duplicates,
                                                    context: .init(text: yaml, mark: firstMark))
        }
    }

    // MARK: - Conversions

    private func tag(_ name: String?) -> Tag {
        return Tag(name.map(Tag.Name.init(rawValue:)) ?? .implicit, resolver)
    }

    private func mark(line: UInt, column: UInt) -> Mark? {
        guard line > 0, column > 0 else { return nil }
        return yaml.mark(atLine: Int(line), byteColumn: Int(column))
    }

    private func scalarStyle(_ style: YAMLNode.ScalarStyle) -> Node.Scalar.Style {
        switch style {
        case .plain: return .plain
        case .singleQuoted: return .singleQuoted
        case .doubleQuoted: return .doubleQuoted
        case .literal: return .literal
        case .folded: return .folded
        case .any: return .any
        @unknown default: return .any
        }
    }

    private func mappingStyle(_ style: YAMLNode.CollectionStyle) -> Node.Mapping.Style {
        switch style {
        case .block: return .block
        case .flow: return .flow
        case .any: return .any
        @unknown default: return .any
        }
    }

    private func sequenceStyle(_ style: YAMLNode.CollectionStyle) -> Node.Sequence.Style {
        switch style {
        case .block: return .block
        case .flow: return .flow
        case .any: return .any
        @unknown default: return .any
        }
    }
}
