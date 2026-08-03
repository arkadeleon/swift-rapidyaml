//
//  Composer.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
internal import CRapidYAML

/// Builds a `Node` tree out of a parsed rapidyaml tree.
///
/// This mirrors the composition half of Yams' `Parser`: aliases are dereferenced to the node
/// their anchor names, rather than surfacing as `Node.alias`, and duplicate mapping keys are
/// rejected. `Parser` owns one of these for the length of a stream, so anchors carry from one
/// document to the next, as they do in Yams.
struct Composer {

    /// The YAML source, carried only so that a failure can report it.
    private let yaml: String

    /// The resolver every composed node's `Tag` is built with.
    private let resolver: Resolver

    /// The constructor every composed node's `Tag` is built with.
    private let constructor: Constructor

    /// The source split into lines, so that a mark costs one line rather than a walk from the top.
    private let lineIndex: LineIndex

    /// The tree being read. Held so that the scalars the records point at stay alive.
    private let tree: ParsedTree

    /// The nodes named so far by an anchor. An alias can only refer to an anchor that has already
    /// been composed, which is what makes a recursive document impossible.
    private var anchors: [Anchor: Node] = [:]

    init(yaml: String, tree: ParsedTree, resolver: Resolver, constructor: Constructor) {
        self.yaml = yaml
        self.tree = tree
        self.lineIndex = LineIndex(yaml)
        self.resolver = resolver
        self.constructor = constructor
    }

    /// Composes one document of the stream.
    ///
    /// - parameter document: The bridged root of a single document.
    ///
    /// - returns: The document's root node. A document with no contents composes to an empty
    ///            scalar, which is what libyaml's empty scalar event gives Yams.
    ///
    /// - throws: `YAMLError` if the document cannot be composed.
    mutating func compose(_ document: YAMLNodeID) throws -> Node {
        let record = tree.read(document)
        switch record.kind {
        case .document, .unknown, .stream:
            return .scalar(.init(""))
        default:
            return try value(of: document, record)
        }
    }

    // MARK: - Composition

    /// Composes the node on the value side of `node` — the whole node, unless it is a child of a
    /// mapping, in which case this is the pair's value.
    private mutating func value(of node: YAMLNodeID, _ record: YAMLNodeRecord) throws -> Node {
        let mark = mark(line: record.valueLine, column: record.valueColumn)

        if let alias = record.valueAlias.string {
            return try dereference(alias, at: mark)
        }

        let anchor = record.valueAnchor.string.map(Anchor.init(rawValue:))

        let composed: Node
        switch record.kind {
        case .mapping:
            var pairs: [(Node, Node)] = []
            pairs.reserveCapacity(record.childCount)
            var child = tree.firstChild(of: node)
            while let current = child {
                let childRecord = tree.read(current)
                pairs.append((try key(of: childRecord), try value(of: current, childRecord)))
                child = tree.nextSibling(of: current)
            }
            try checkDuplicates(in: pairs.map { $0.0 })
            composed = .mapping(.init(pairs, tag(record.valueTag.string),
                                      mappingStyle(record.collectionStyle), mark, anchor))
        case .sequence:
            var nodes: [Node] = []
            nodes.reserveCapacity(record.childCount)
            var child = tree.firstChild(of: node)
            while let current = child {
                nodes.append(try value(of: current, tree.read(current)))
                child = tree.nextSibling(of: current)
            }
            composed = .sequence(.init(nodes, tag(record.valueTag.string),
                                       sequenceStyle(record.collectionStyle), mark, anchor))
        default:
            // A value that was written but left empty — `key:` — has no scalar of its own.
            let style = scalarStyle(record.valueStyle)
            composed = .scalar(.init(record.value.string ?? "",
                                     scalarTag(record.valueTag.string, style: style), style, mark, anchor))
        }

        register(anchor, for: composed)
        return composed
    }

    /// Composes the key side of a mapping's child.
    ///
    /// - note: rapidyaml stores a key as a scalar, so a complex key — `? [a, b]` — cannot be
    ///         represented. Yams supports those through libyaml's event stream.
    private mutating func key(of record: YAMLNodeRecord) throws -> Node {
        let mark = mark(line: record.keyLine, column: record.keyColumn)

        if let alias = record.keyAlias.string {
            return try dereference(alias, at: mark)
        }

        let anchor = record.keyAnchor.string.map(Anchor.init(rawValue:))
        let style = scalarStyle(record.keyStyle)
        let composed = Node.scalar(.init(record.key.string ?? "",
                                         scalarTag(record.keyTag.string, style: style), style, mark, anchor))

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
        return Tag(name.map(Tag.Name.init(rawValue:)) ?? .implicit, resolver, constructor)
    }

    /// The tag for a scalar, honouring the non-specific tag its style implies.
    ///
    /// A quoted, literal or folded scalar carries YAML's `!` tag, meaning "do not resolve me by
    /// value": `'true'` is the string `true`, not a boolean. Only a plain scalar is resolved from
    /// its contents. libyaml reports this to Yams as `quoted_implicit`, and Yams tags the scalar
    /// `.str`; rapidyaml only reports the style, so the same conclusion is drawn from that.
    private func scalarTag(_ name: String?, style: Node.Scalar.Style) -> Tag {
        guard name == nil else { return tag(name) }
        switch style {
        case .singleQuoted, .doubleQuoted, .literal, .folded:
            return Tag(.str, resolver, constructor)
        case .plain, .any:
            return tag(nil)
        }
    }

    private func mark(line: Int, column: Int) -> Mark? {
        guard line > 0, column > 0 else { return nil }
        return lineIndex.mark(atLine: Int(line), byteColumn: Int(column))
    }

    private func scalarStyle(_ style: YAMLScalarStyle) -> Node.Scalar.Style {
        switch style {
        case .plain: return .plain
        case .singleQuoted: return .singleQuoted
        case .doubleQuoted: return .doubleQuoted
        case .literal: return .literal
        case .folded: return .folded
        default: return .any
        }
    }

    private func mappingStyle(_ style: YAMLCollectionStyle) -> Node.Mapping.Style {
        switch style {
        case .block: return .block
        case .flow: return .flow
        default: return .any
        }
    }

    private func sequenceStyle(_ style: YAMLCollectionStyle) -> Node.Sequence.Style {
        switch style {
        case .block: return .block
        case .flow: return .flow
        default: return .any
        }
    }
}
