//
//  Emitter.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
internal import CRapidYAML

/// Produce a YAML string from objects.
///
/// - parameter objects:       Sequence of Objects.
/// - parameter canonical:     Output should be the "canonical" format as in the YAML specification.
/// - parameter indent:        The indentation increment.
/// - parameter width:         The preferred line width. @c -1 means unlimited.
/// - parameter allowUnicode:  Unescaped non-ASCII characters are allowed if true.
/// - parameter lineBreak:     Preferred line break.
/// - parameter explicitStart: Explicit document start `---`.
/// - parameter explicitEnd:   Explicit document end `...`.
/// - parameter version:       YAML version directive.
/// - parameter sortKeys:      Whether or not to sort Mapping keys in lexicographic order.
/// - parameter sequenceStyle: The style for sequences (arrays / lists)
/// - parameter mappingStyle:  The style for mappings (dictionaries)
///
/// - returns: YAML string.
///
/// - throws: `YAMLError`.
public func dump<Objects>(
    objects: Objects,
    canonical: Bool = false,
    indent: Int = 0,
    width: Int = 0,
    allowUnicode: Bool = false,
    lineBreak: Emitter.LineBreak = .ln,
    explicitStart: Bool = false,
    explicitEnd: Bool = false,
    version: (major: Int, minor: Int)? = nil,
    sortKeys: Bool = false,
    sequenceStyle: Node.Sequence.Style = .any,
    mappingStyle: Node.Mapping.Style = .any,
    newLineScalarStyle: Node.Scalar.Style = .any) throws -> String
    where Objects: Sequence {
    func representable(from object: Any) throws -> NodeRepresentable {
        if let representable = object as? NodeRepresentable {
            return representable
        }
        throw YAMLError.emitter(problem: "\(object) does not conform to NodeRepresentable!")
    }
    let nodes = try objects.map(representable(from:)).map { try $0.represented() }
    return try serialize(
        nodes: nodes,
        canonical: canonical,
        indent: indent,
        width: width,
        allowUnicode: allowUnicode,
        lineBreak: lineBreak,
        explicitStart: explicitStart,
        explicitEnd: explicitEnd,
        version: version,
        sortKeys: sortKeys,
        sequenceStyle: sequenceStyle,
        mappingStyle: mappingStyle,
        newLineScalarStyle: newLineScalarStyle
    )
}

/// Produce a YAML string from an object.
///
/// - parameter object:        Object.
/// - parameter canonical:     Output should be the "canonical" format as in the YAML specification.
/// - parameter indent:        The indentation increment.
/// - parameter width:         The preferred line width. @c -1 means unlimited.
/// - parameter allowUnicode:  Unescaped non-ASCII characters are allowed if true.
/// - parameter lineBreak:     Preferred line break.
/// - parameter explicitStart: Explicit document start `---`.
/// - parameter explicitEnd:   Explicit document end `...`.
/// - parameter version:       YAML version directive.
/// - parameter sortKeys:      Whether or not to sort Mapping keys in lexicographic order.
/// - parameter sequenceStyle: The style for sequences (arrays / lists)
/// - parameter mappingStyle:  The style for mappings (dictionaries)
///
/// - returns: YAML string.
///
/// - throws: `YAMLError`.
public func dump(
    object: Any?,
    canonical: Bool = false,
    indent: Int = 0,
    width: Int = 0,
    allowUnicode: Bool = false,
    lineBreak: Emitter.LineBreak = .ln,
    explicitStart: Bool = false,
    explicitEnd: Bool = false,
    version: (major: Int, minor: Int)? = nil,
    sortKeys: Bool = false,
    sequenceStyle: Node.Sequence.Style = .any,
    mappingStyle: Node.Mapping.Style = .any,
    newLineScalarStyle: Node.Scalar.Style = .any,
    redundancyAliasingStrategy: RedundancyAliasingStrategy? = nil) throws -> String {
    return try serialize(
        node: object.represented(),
        canonical: canonical,
        indent: indent,
        width: width,
        allowUnicode: allowUnicode,
        lineBreak: lineBreak,
        explicitStart: explicitStart,
        explicitEnd: explicitEnd,
        version: version,
        sortKeys: sortKeys,
        sequenceStyle: sequenceStyle,
        mappingStyle: mappingStyle,
        newLineScalarStyle: newLineScalarStyle,
        redundancyAliasingStrategy: redundancyAliasingStrategy
    )
}

/// Produce a YAML string from a sequence of `Node`s.
///
/// - parameter nodes:         Sequence of `Node`s.
/// - parameter canonical:     Output should be the "canonical" format as in the YAML specification.
/// - parameter indent:        The indentation increment.
/// - parameter width:         The preferred line width. @c -1 means unlimited.
/// - parameter allowUnicode:  Unescaped non-ASCII characters are allowed if true.
/// - parameter lineBreak:     Preferred line break.
/// - parameter explicitStart: Explicit document start `---`.
/// - parameter explicitEnd:   Explicit document end `...`.
/// - parameter version:       YAML version directive.
/// - parameter sortKeys:      Whether or not to sort Mapping keys in lexicographic order.
/// - parameter sequenceStyle: The style for sequences (arrays / lists)
/// - parameter mappingStyle:  The style for mappings (dictionaries)
///
/// - returns: YAML string.
///
/// - throws: `YAMLError`.
public func serialize<Nodes>(
    nodes: Nodes,
    canonical: Bool = false,
    indent: Int = 0,
    width: Int = 0,
    allowUnicode: Bool = false,
    lineBreak: Emitter.LineBreak = .ln,
    explicitStart: Bool = false,
    explicitEnd: Bool = false,
    version: (major: Int, minor: Int)? = nil,
    sortKeys: Bool = false,
    sequenceStyle: Node.Sequence.Style = .any,
    mappingStyle: Node.Mapping.Style = .any,
    newLineScalarStyle: Node.Scalar.Style = .any,
    redundancyAliasingStrategy: RedundancyAliasingStrategy? = nil) throws -> String
    where Nodes: Sequence, Nodes.Iterator.Element == Node {
    let emitter = Emitter(
        canonical: canonical,
        indent: indent,
        width: width,
        allowUnicode: allowUnicode,
        lineBreak: lineBreak,
        explicitStart: explicitStart,
        explicitEnd: explicitEnd,
        version: version,
        sortKeys: sortKeys,
        sequenceStyle: sequenceStyle,
        mappingStyle: mappingStyle,
        newLineScalarStyle: newLineScalarStyle,
        redundancyAliasingStrategy: redundancyAliasingStrategy
    )
    try emitter.open()
    try nodes.forEach(emitter.serialize)
    try emitter.close()
    return String(data: emitter.data, encoding: .utf8)!
}

/// Produce a YAML string from a `Node`.
///
/// - parameter node:          `Node`.
/// - parameter canonical:     Output should be the "canonical" format as in the YAML specification.
/// - parameter indent:        The indentation increment.
/// - parameter width:         The preferred line width. @c -1 means unlimited.
/// - parameter allowUnicode:  Unescaped non-ASCII characters are allowed if true.
/// - parameter lineBreak:     Preferred line break.
/// - parameter explicitStart: Explicit document start `---`.
/// - parameter explicitEnd:   Explicit document end `...`.
/// - parameter version:       YAML version directive.
/// - parameter sortKeys:      Whether or not to sort Mapping keys in lexicographic order.
/// - parameter sequenceStyle: The style for sequences (arrays / lists)
/// - parameter mappingStyle:  The style for mappings (dictionaries)
///
/// - returns: YAML string.
///
/// - throws: `YAMLError`.
public func serialize(
    node: Node,
    canonical: Bool = false,
    indent: Int = 0,
    width: Int = 0,
    allowUnicode: Bool = false,
    lineBreak: Emitter.LineBreak = .ln,
    explicitStart: Bool = false,
    explicitEnd: Bool = false,
    version: (major: Int, minor: Int)? = nil,
    sortKeys: Bool = false,
    sequenceStyle: Node.Sequence.Style = .any,
    mappingStyle: Node.Mapping.Style = .any,
    newLineScalarStyle: Node.Scalar.Style = .any,
    redundancyAliasingStrategy: RedundancyAliasingStrategy? = nil) throws -> String {
    return try serialize(
        nodes: [node],
        canonical: canonical,
        indent: indent,
        width: width,
        allowUnicode: allowUnicode,
        lineBreak: lineBreak,
        explicitStart: explicitStart,
        explicitEnd: explicitEnd,
        version: version,
        sortKeys: sortKeys,
        sequenceStyle: sequenceStyle,
        mappingStyle: mappingStyle,
        newLineScalarStyle: newLineScalarStyle,
        redundancyAliasingStrategy: redundancyAliasingStrategy
    )
}

/// Class responsible for emitting YAML.
///
/// - note: Yams drives libyaml's event-based emitter, which lets it honour options such as
///         `canonical`, `indent` and `width`. rapidyaml emits a whole tree at a time and offers
///         no equivalent, so those options are rejected rather than silently ignored — see
///         `unsupportedOption`.
public final class Emitter {
    /// Line break options to use when emitting YAML.
    public enum LineBreak {
        /// Use CR for line breaks (Mac style).
        case cr
        /// Use LN for line breaks (Unix style).
        case ln
        /// Use CR LN for line breaks (DOS style).
        case crln
    }

    /// Retrieve this Emitter's binary output.
    public internal(set) var data = Data()

    /// Configuration options to use when emitting YAML.
    public struct Options {
        /// Set if the output should be in the "canonical" format described in the YAML specification.
        ///
        /// - note: Unsupported: rapidyaml has no canonical mode.
        public var canonical: Bool = false
        /// Set the indentation value.
        ///
        /// - note: Unsupported: rapidyaml always indents by two spaces.
        public var indent: Int = 0
        /// Set the preferred line width. -1 means unlimited.
        ///
        /// - note: Unsupported: rapidyaml only wraps multi-line flow containers.
        public var width: Int = 0
        /// Set if unescaped non-ASCII characters are allowed.
        ///
        /// - note: Unsupported: rapidyaml always writes non-ASCII unescaped, which is what
        ///         `allowUnicode: true` asks for. Setting it to `true` is therefore accepted.
        public var allowUnicode: Bool = false
        /// Set the preferred line break.
        ///
        /// - note: Unsupported beyond `.ln`: rapidyaml always writes `\n`.
        public var lineBreak: LineBreak = .ln
        /// Set to emit an explicit document start marker.
        public var explicitStart: Bool = false
        /// Set to emit an explicit document end marker.
        ///
        /// - note: Unsupported: rapidyaml never writes `...`.
        public var explicitEnd: Bool = false

        /// The `%YAML` directive value or nil.
        ///
        /// - note: Unsupported: rapidyaml does not emit version directives.
        public var version: (major: Int, minor: Int)?

        /// Set if emitter should sort keys in lexicographic order.
        public var sortKeys: Bool = false

        /// Set the style for sequences (arrays / lists)
        public var sequenceStyle: Node.Sequence.Style = .any

        /// Set the style for mappings (dictionaries)
        public var mappingStyle: Node.Mapping.Style = .any

        /// Set the style for scalars that include newlines
        public var newLineScalarStyle: Node.Scalar.Style = .any

        /// Redundancy aliasing strategy to use when encoding. Defaults to nil
        public var redundancyAliasingStrategy: RedundancyAliasingStrategy?

        /// Create `Emitter.Options` with the specified values.
        ///
        /// - parameter canonical:     Set if the output should be in the "canonical" format described in the YAML
        ///                            specification.
        /// - parameter indent:        Set the indentation value.
        /// - parameter width:         Set the preferred line width. -1 means unlimited.
        /// - parameter allowUnicode:  Set if unescaped non-ASCII characters are allowed.
        /// - parameter lineBreak:     Set the preferred line break.
        /// - parameter explicitStart: Explicit document start `---`.
        /// - parameter explicitEnd:   Explicit document end `...`.
        /// - parameter version:       The `%YAML` directive value or nil.
        /// - parameter sortKeys:      Set if emitter should sort keys in lexicographic order.
        /// - parameter sequenceStyle: Set the style for sequences (arrays / lists)
        /// - parameter mappingStyle:  Set the style for mappings (dictionaries)
        /// - parameter newLineScalarStyle: Set the style for newline-containing scalars
        /// - parameter redundancyAliasingStrategy: Set the strategy for identifying
        /// redundant structures and automatically aliasing them
        public init(canonical: Bool = false, indent: Int = 0, width: Int = 0, allowUnicode: Bool = false,
                    lineBreak: Emitter.LineBreak = .ln,
                    explicitStart: Bool = false,
                    explicitEnd: Bool = false,
                    version: (major: Int, minor: Int)? = nil,
                    sortKeys: Bool = false, sequenceStyle: Node.Sequence.Style = .any,
                    mappingStyle: Node.Mapping.Style = .any,
                    newLineScalarStyle: Node.Scalar.Style = .any,
                    redundancyAliasingStrategy: RedundancyAliasingStrategy? = nil) {
            self.canonical = canonical
            self.indent = indent
            self.width = width
            self.allowUnicode = allowUnicode
            self.lineBreak = lineBreak
            self.explicitStart = explicitStart
            self.explicitEnd = explicitEnd
            self.version = version
            self.sortKeys = sortKeys
            self.sequenceStyle = sequenceStyle
            self.mappingStyle = mappingStyle
            self.newLineScalarStyle = newLineScalarStyle
            self.redundancyAliasingStrategy = redundancyAliasingStrategy
        }

        /// The name of the first option set to something rapidyaml cannot honour, if any.
        var unsupportedOption: String? {
            if canonical { return "canonical" }
            if indent != 0 { return "indent" }
            if width != 0 { return "width" }
            if explicitEnd { return "explicitEnd" }
            if version != nil { return "version" }
            if case .ln = lineBreak {} else { return "lineBreak" }
            return nil
        }
    }

    /// Configuration options to use when emitting YAML.
    public var options: Options

    /// Create an `Emitter` with the specified options.
    ///
    /// - parameter canonical:     Set if the output should be in the "canonical" format described in the YAML
    ///                            specification.
    /// - parameter indent:        Set the indentation value.
    /// - parameter width:         Set the preferred line width. -1 means unlimited.
    /// - parameter allowUnicode:  Set if unescaped non-ASCII characters are allowed.
    /// - parameter lineBreak:     Set the preferred line break.
    /// - parameter explicitStart: Explicit document start `---`.
    /// - parameter explicitEnd:   Explicit document end `...`.
    /// - parameter version:       The `%YAML` directive value or nil.
    /// - parameter sortKeys:      Set if emitter should sort keys in lexicographic order.
    /// - parameter sequenceStyle: Set the style for sequences (arrays / lists)
    /// - parameter mappingStyle:  Set the style for mappings (dictionaries)
    /// - parameter newLineScalarStyle: Set the style for newline-containing scalars
    /// - parameter redundancyAliasingStrategy: Set the strategy for identifying redundant
    /// structures and automatically aliasing them
    public init(canonical: Bool = false,
                indent: Int = 0,
                width: Int = 0,
                allowUnicode: Bool = false,
                lineBreak: LineBreak = .ln,
                explicitStart: Bool = false,
                explicitEnd: Bool = false,
                version: (major: Int, minor: Int)? = nil,
                sortKeys: Bool = false,
                sequenceStyle: Node.Sequence.Style = .any,
                mappingStyle: Node.Mapping.Style = .any,
                newLineScalarStyle: Node.Scalar.Style = .any,
                redundancyAliasingStrategy: RedundancyAliasingStrategy? = nil) {
        options = Options(canonical: canonical,
                          indent: indent,
                          width: width,
                          allowUnicode: allowUnicode,
                          lineBreak: lineBreak,
                          explicitStart: explicitStart,
                          explicitEnd: explicitEnd,
                          version: version,
                          sortKeys: sortKeys,
                          sequenceStyle: sequenceStyle,
                          mappingStyle: mappingStyle,
                          newLineScalarStyle: newLineScalarStyle,
                          redundancyAliasingStrategy: redundancyAliasingStrategy)
    }

    /// Open & initialize the emitter.
    ///
    /// - throws: `YAMLError` if the `Emitter` was already opened or closed.
    public func open() throws {
        switch state {
        case .initialized:
            if let unsupported = options.unsupportedOption {
                throw YAMLError.emitter(problem: "\(unsupported) is not supported by the rapidyaml emitter")
            }
            state = .opened
        case .opened:
            throw YAMLError.emitter(problem: "serializer is already opened")
        case .closed:
            throw YAMLError.emitter(problem: "serializer is closed")
        }
    }

    /// Close the `Emitter.`
    ///
    /// - throws: `YAMLError` if the `Emitter` hasn't yet been initialized.
    public func close() throws {
        switch state {
        case .initialized:
            throw YAMLError.emitter(problem: "serializer is not opened")
        case .opened:
            // rapidyaml emits a whole tree at a time, so nothing is written until the stream is
            // complete and every document is known.
            var emitted = try YAMLEmitter.emit(documents, explicitStart: options.explicitStart)
            // rapidyaml leaves a flow-style root — `{}`, `[1,2]` — without one.
            if !emitted.hasSuffix("\n") {
                emitted += "\n"
            }
            data = Data(emitted.utf8)
            state = .closed
        case .closed:
            break // do nothing
        }
    }

    /// Ingest a `Node` to include when emitting the YAML output.
    ///
    /// - parameter node: The `Node` to serialize.
    ///
    /// - throws: `YAMLError` if the `Emitter` hasn't yet been opened or has been closed.
    public func serialize(node: Node) throws {
        switch state {
        case .initialized:
            throw YAMLError.emitter(problem: "serializer is not opened")
        case .opened:
            break
        case .closed:
            throw YAMLError.emitter(problem: "serializer is closed")
        }
        documents.append(describe(node))
    }

    // MARK: Private

    private enum State { case initialized, opened, closed }
    private var state: State = .initialized

    /// The documents ingested so far, already converted for the bridge.
    private var documents: [YAMLEmitterNode] = []
}

// MARK: Implementation Details

extension Emitter {

    /// Converts a `Node` into the description the Objective-C++ emitter builds a tree from.
    private func describe(_ node: Node, key: Node? = nil) -> YAMLEmitterNode {
        let description = YAMLEmitterNode()

        if let key {
            switch key {
            case .scalar(let scalar):
                description.key = scalar.string
                description.keyTag = tagName(of: scalar)
                description.keyAnchor = scalar.anchor?.rawValue
                description.keyStyle = scalarStyle(scalar.style)
            default:
                // rapidyaml cannot represent a container as a key, so it is written as its
                // description — the same limitation composition has in the other direction.
                description.key = key.string ?? ""
                description.keyStyle = .singleQuoted
            }
        }

        switch node {
        case .scalar(let scalar):
            description.kind = .scalar
            description.value = scalar.string
            description.valueTag = tagName(of: scalar)
            description.valueAnchor = scalar.anchor?.rawValue
            description.valueStyle = scalarStyle(scalar.style)
        case .sequence(let sequence):
            description.kind = .sequence
            description.valueTag = tagName(of: sequence.resolvedTag, default: .seq)
            description.valueAnchor = sequence.anchor?.rawValue
            description.collectionStyle = collectionStyle(sequence.style, default: options.sequenceStyle)
            description.children = sequence.map { describe($0) }
        case .mapping(let mapping):
            description.kind = .mapping
            description.valueTag = tagName(of: mapping.resolvedTag, default: .map)
            description.valueAnchor = mapping.anchor?.rawValue
            description.collectionStyle = collectionStyle(mapping.style, default: options.mappingStyle)
            if options.sortKeys {
                description.children = mapping.keys.sorted().map { describe(mapping[$0]!, key: $0) }
            } else {
                description.children = mapping.map { describe($0.value, key: $0.key) }
            }
        case .alias(let alias):
            description.kind = .scalar
            description.valueAlias = alias.anchor.rawValue
        }

        return description
    }

    /// The tag to write for a scalar, or `nil` when reading it back would produce it anyway.
    ///
    /// Yams hands libyaml `plain_implicit` and `quoted_implicit`, leaving libyaml to drop the tag
    /// when it is redundant. rapidyaml writes whatever tag the tree carries, so the same decision
    /// is made here instead.
    private func tagName(of scalar: Node.Scalar) -> String? {
        let resolved = scalar.resolvedTag.name
        guard resolved != .implicit else { return nil }

        // A quoted, literal or folded scalar already carries YAML's non-specific tag, which means
        // `.str` — writing `!!str` on top of it would be noise.
        if resolved == .str, scalar.style != .plain, scalar.style != .any {
            return nil
        }

        guard resolved != Resolver.default.resolveTag(from: scalar.string) else { return nil }
        return shorthand(resolved)
    }

    /// The tag to write, or `nil` when it is the one the value would resolve to anyway.
    private func tagName(of tag: Tag, default defaultName: Tag.Name) -> String? {
        return tag.name == defaultName || tag.name == .implicit ? nil : shorthand(tag.name)
    }

    /// The form libyaml writes a tag in: `tag:yaml.org,2002:binary` becomes `!!binary`, a name
    /// already carrying a handle is left alone, and anything else takes the verbatim form
    /// `!<name>` — which is what reading it back turns into that same name again.
    private func shorthand(_ name: Tag.Name) -> String {
        let prefix = "tag:yaml.org,2002:"
        if name.rawValue.hasPrefix(prefix) {
            return "!!" + name.rawValue.dropFirst(prefix.count)
        }
        if name.rawValue.hasPrefix("!") {
            return name.rawValue
        }
        return "!<\(name.rawValue)>"
    }

    private func scalarStyle(_ style: Node.Scalar.Style) -> YAMLScalarStyle {
        switch style {
        case .plain: return .plain
        case .singleQuoted: return .singleQuoted
        case .doubleQuoted: return .doubleQuoted
        case .literal: return .literal
        case .folded: return .folded
        case .any: return .any
        }
    }

    private func collectionStyle(_ style: Node.Sequence.Style,
                                 default defaultStyle: Node.Sequence.Style) -> YAMLCollectionStyle {
        switch style == .any ? defaultStyle : style {
        case .block: return .block
        case .flow: return .flow
        case .any: return .any
        }
    }

    private func collectionStyle(_ style: Node.Mapping.Style,
                                 default defaultStyle: Node.Mapping.Style) -> YAMLCollectionStyle {
        switch style == .any ? defaultStyle : style {
        case .block: return .block
        case .flow: return .flow
        case .any: return .any
        }
    }
}

extension YAMLEmitter {

    /// Emits `documents`, reporting a failure as a `YAMLError` rather than as the `NSError` the
    /// Objective-C++ bridge produces.
    fileprivate static func emit(_ documents: [YAMLEmitterNode], explicitStart: Bool) throws -> String {
        do {
            return try YAMLEmitter.emitDocuments(documents, explicitStart: explicitStart)
        } catch {
            throw YAMLError.emitter(problem: (error as NSError).localizedDescription)
        }
    }
}
