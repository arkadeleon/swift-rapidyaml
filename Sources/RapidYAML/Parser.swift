//
//  Parser.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
internal import YAMLNode

/// Parse all YAML documents in a String
/// and produce corresponding Swift objects.
///
/// - parameter yaml: String
/// - parameter resolver: Resolver
/// - parameter constructor: Constructor
/// - parameter encoding: Parser.Encoding
///
/// - returns: YAMLSequence<Any>
///
/// - throws: YAMLError
public func load_all(yaml: String,
                     _ resolver: Resolver = .default,
                     _ constructor: Constructor = .default,
                     _ encoding: Parser.Encoding = .default) throws -> YAMLSequence<Any> {
    let parser = try Parser(yaml: yaml, resolver: resolver, constructor: constructor, encoding: encoding)
    return YAMLSequence { try parser.nextRoot()?.any }
}

/// Parse the first YAML document in a String
/// and produce the corresponding Swift object.
///
/// - parameter yaml: String
/// - parameter resolver: Resolver
/// - parameter constructor: Constructor
/// - parameter encoding: Parser.Encoding
///
/// - returns: Any?
///
/// - throws: YAMLError
public func load(yaml: String,
                 _ resolver: Resolver = .default,
                 _ constructor: Constructor = .default,
                 _ encoding: Parser.Encoding = .default) throws -> Any? {
    return try Parser(yaml: yaml, resolver: resolver, constructor: constructor, encoding: encoding).singleRoot()?.any
}

/// Parse all YAML documents in a String
/// and produce corresponding representation trees.
///
/// - parameter yaml: String
/// - parameter resolver: Resolver
/// - parameter constructor: Constructor
/// - parameter encoding: Parser.Encoding
///
/// - returns: YAMLSequence<Node>
///
/// - throws: YAMLError
public func compose_all(yaml: String,
                        _ resolver: Resolver = .default,
                        _ constructor: Constructor = .default,
                        _ encoding: Parser.Encoding = .default) throws -> YAMLSequence<Node> {
    let parser = try Parser(yaml: yaml, resolver: resolver, constructor: constructor, encoding: encoding)
    return YAMLSequence(parser.nextRoot)
}

/// Parse the first YAML document in a String
/// and produce the corresponding representation tree.
///
/// - parameter yaml: String
/// - parameter resolver: Resolver
/// - parameter constructor: Constructor
/// - parameter encoding: Parser.Encoding
///
/// - returns: Node?
///
/// - throws: YAMLError
public func compose(yaml: String,
                    _ resolver: Resolver = .default,
                    _ constructor: Constructor = .default,
                    _ encoding: Parser.Encoding = .default) throws -> Node? {
    return try Parser(yaml: yaml, resolver: resolver, constructor: constructor, encoding: encoding).singleRoot()
}

/// Sequence that holds an error.
public struct YAMLSequence<T>: Sequence, IteratorProtocol {
    /// This sequence's error, if any.
    public private(set) var error: Swift.Error?

    /// `Swift.Sequence.next()`.
    public mutating func next() -> T? {
        do {
            return try closure()
        } catch {
            self.error = error
            return nil
        }
    }

    fileprivate init(_ closure: @escaping () throws -> T?) {
        self.closure = closure
    }

    private let closure: () throws -> T?
}

/// Parses YAML strings.
public final class Parser {
    /// YAML string.
    public let yaml: String
    /// Resolver.
    public let resolver: Resolver
    /// Constructor.
    public let constructor: Constructor

    /// Encoding.
    ///
    /// - note: Yams needs this because it must tell libyaml which encoding the bytes are in, and
    ///         its `.default` consults a `YAMS_DEFAULT_ENCODING` environment variable. rapidyaml
    ///         only ever reads UTF-8, and a `String` is handed to it as UTF-8 whatever this says,
    ///         so it has an effect only on the `Data` initializer, where it selects how the bytes
    ///         are decoded into a `String`.
    public enum Encoding: String, Sendable {
        /// UTF-8.
        case utf8
        /// UTF-16, in the platform's native endianness.
        case utf16

        /// The default encoding, UTF-8.
        public static var `default`: Encoding { .utf8 }

        /// The equivalent `Swift.Encoding` value for `self`.
        public var swiftStringEncoding: String.Encoding {
            switch self {
            case .utf8:
                return .utf8
            case .utf16:
                return .utf16
            }
        }
    }

    /// Encoding
    public let encoding: Encoding

    /// Set up a `Parser` with a `String` value as input.
    ///
    /// - parameter string: YAML string.
    /// - parameter resolver: Resolver, `.default` if omitted.
    /// - parameter constructor: Constructor, `.default` if omitted.
    /// - parameter encoding: Encoding, `.default` if omitted.
    ///
    /// - throws: `YAMLError`.
    public init(yaml string: String,
                resolver: Resolver = .default,
                constructor: Constructor = .default,
                encoding: Encoding = .default) throws {
        yaml = string
        self.resolver = resolver
        self.constructor = constructor
        self.encoding = encoding
        self.composer = Composer(yaml: string, resolver: resolver, constructor: constructor)

        let root: YAMLNode
        do {
            root = try YAMLNode(yamlString: string)
        } catch {
            // The bridge reports failures as an NSError; YAMLError is what callers expect.
            throw YAMLError(from: error as NSError, with: string)
        }

        // rapidyaml only builds a STREAM root when the source holds more than one document;
        // a lone document is its own root, and an empty source has no document at all.
        switch root.kind {
        case .stream:
            documents = root.children
        case .unknown:
            documents = []
        default:
            documents = [root]
        }
    }

    /// Set up a `Parser` with a `Data` value as input.
    ///
    /// - parameter data: YAML Data encoded using the `encoding` encoding.
    /// - parameter resolver: Resolver, `.default` if omitted.
    /// - parameter constructor: Constructor, `.default` if omitted.
    /// - parameter encoding: Encoding, `.default` if omitted.
    ///
    /// - throws: `YAMLError`.
    public convenience init(yaml data: Data,
                            resolver: Resolver = .default,
                            constructor: Constructor = .default,
                            encoding: Encoding = .default) throws {
        guard let yamlString = String(data: data, encoding: encoding.swiftStringEncoding) else {
            throw YAMLError.dataCouldNotBeDecoded(encoding: encoding.swiftStringEncoding)
        }

        try self.init(
            yaml: yamlString,
            resolver: resolver,
            constructor: constructor,
            encoding: encoding
        )
    }

    /// Parse next document and return root Node.
    ///
    /// - returns: next Node.
    ///
    /// - throws: `YAMLError`.
    public func nextRoot() throws -> Node? {
        guard index < documents.count else { return nil }
        defer { index += 1 }
        return try composer.compose(documents[index])
    }

    /// Parses the document expecting a single root Node and returns it.
    ///
    /// - returns: Single root Node.
    ///
    /// - throws: `YAMLError`.
    public func singleRoot() throws -> Node? {
        guard let node = try nextRoot() else { return nil }
        if index < documents.count {
            throw YAMLError.composer(
                context: YAMLError.Context(text: "expected a single document in the stream",
                                           mark: Mark(line: 1, column: 1)),
                problem: "but found another document", startMark(of: documents[index]),
                yaml: yaml
            )
        }
        return node
    }

    // MARK: - Private Members

    /// The documents of the stream, in source order.
    private let documents: [YAMLNode]

    /// How far `nextRoot()` has read.
    private var index = 0

    /// Held for the length of the stream, so that anchors carry across documents as in Yams.
    private var composer: Composer

    private func startMark(of document: YAMLNode) -> Mark {
        let line = document.hasKey ? document.keyLine : document.valueLine
        let column = document.hasKey ? document.keyColumn : document.valueColumn
        guard line > 0, column > 0 else { return Mark(line: 1, column: 1) }
        return LineIndex(yaml).mark(atLine: Int(line), byteColumn: Int(column))
    }
}
