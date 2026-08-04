//
//  YAMLDecoder.swift
//  RapidYAML
//
//  Created by Leon Li on 2025/6/12.
//

import Foundation

/// `Codable`-style `Decoder` that can be used to decode a `Decodable` type from a given `String` and optional
/// user info mapping. Similar to `Foundation.JSONDecoder`.
public class YAMLDecoder {

    /// Options to use when decoding from YAML.
    public struct Options {

        /// Create `YAMLDecoder.Options` with the specified values.
        public init(encoding: String.Encoding = .utf8,
                    aliasDereferencingStrategy: AliasDereferencingStrategy? = nil) {
            self.encoding = encoding
            self.aliasDereferencingStrategy = aliasDereferencingStrategy
        }

        /// String encoding used when decoding from `Data`.
        public var encoding: String.Encoding = .utf8

        /// Alias dereferencing strategy to use when decoding. Defaults to nil
        public var aliasDereferencingStrategy: AliasDereferencingStrategy?
    }

    /// Options to use when decoding from YAML.
    public var options = Options()

    /// Creates a `YAMLDecoder` instance.
    ///
    /// - parameter encoding: String encoding.
    public convenience init(encoding: String.Encoding) {
        self.init()
        self.options.encoding = encoding
    }

    /// Creates a `YAMLDecoder` instance.
    public init() {
    }

    /// Decode a `Decodable` type from a given `Node` and optional user info mapping.
    ///
    /// - parameter type:       `Decodable` type to decode.
    /// - parameter node:       YAML Node to decode.
    /// - parameter userInfo:   Additional key/values which can be used when looking up keys to decode.
    ///
    /// - returns: Returns the decoded type `T`.
    ///
    /// - throws: `DecodingError` or `YAMLError` if something went wrong while decoding.
    public func decode<T>(
        _ type: T.Type = T.self,
        from node: Node,
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) throws -> T where T: Decodable {
        let decoder = _decoder(from: node, userInfo: userInfo)
        let container = try decoder.singleValueContainer()
        return try container.decode(type)
    }

    /// Decode a `Decodable` type from a given `String` and optional user info mapping.
    ///
    /// - parameter type:       `Decodable` type to decode.
    /// - parameter yamlString: YAML string to decode.
    /// - parameter userInfo:   Additional key/values which can be used when looking up keys to decode.
    ///
    /// - returns: Returns the decoded type `T`.
    ///
    /// - throws: `DecodingError` or `YAMLError` if something went wrong while decoding.
    public func decode<T>(
        _ type: T.Type = T.self,
        from yamlString: String,
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) throws -> T where T: Decodable {
        return try processNode(type, from: yamlString) { [type, userInfo] node in
            try self.decode(type, from: node, userInfo: userInfo)
        }
    }

    /// Decode a `Decodable` type from a given `Data` and optional user info mapping.
    ///
    /// - parameter type:       `Decodable` type to decode.
    /// - parameter yamlData:   YAML data to decode.
    /// - parameter userInfo:   Additional key/values which can be used when looking up keys to decode.
    ///
    /// - returns: Returns the decoded type `T`.
    ///
    /// - throws: `DecodingError` or `YAMLError` if something went wrong while decoding.
    public func decode<T>(
        _ type: T.Type = T.self,
        from yamlData: Data,
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) throws -> T where T: Decodable {
        guard let yamlString = String(data: yamlData, encoding: options.encoding) else {
            throw YAMLError.dataCouldNotBeDecoded(encoding: options.encoding)
        }

        return try decode(type, from: yamlString, userInfo: userInfo)
    }
}

extension YAMLDecoder {

    /// Constructs a `_YAMLDecoder` referencing given YAML node to decode with a provided user info.
    ///
    /// - parameter node:     YAML Node to decode.
    /// - parameter userInfo: Additional key/values which can be used when looking up keys to decode.
    ///
    /// - returns: A constructed `_YAMLDecoder` instance.
    ///
    /// - note: This is a single `_YAMLDecoder` constructor for decoding `Decodable`
    ///         and `DecodableWithConfiguration` objects.
    private func _decoder(from node: Node, userInfo: [CodingUserInfoKey: Any]) -> _YAMLDecoder {
        var finalUserInfo = userInfo
        if let dealiasingStrategy = options.aliasDereferencingStrategy {
            finalUserInfo[.aliasDereferencingStrategy] = dealiasingStrategy
        }

        return _YAMLDecoder(referencing: node, userInfo: finalUserInfo)
    }

    /// Returns a value of the type you specify, decoded from a YAML object.
    ///
    /// - parameter type:       The type of the value to decode from the supplied YAML object.
    /// - parameter yamlString: The YAML object `String` to process.
    /// - parameter block:      A block to decode a given object type from the YAML node.
    ///
    /// - returns: A value of the specified type, if the decoder can parse the data.
    ///
    /// - note: This is a single parser function for decoding `Decodable` and `DecodableWithConfiguration` objects.
    private func processNode<T>(
        _ type: T.Type,
        from yamlString: String,
        with block: (_ node: Node) throws -> T
    ) throws -> T {
        do {
            // Yams decodes with `Resolver([.merge])`, and so do we. No constructor needs a tag
            // resolved from a scalar's contents: the numeric ones refuse anything that is not
            // plain, and `Bool` refuses anything already tagged `.str`, which is what composing
            // a quoted scalar produces. That leaves `<<` as the only rule decoding has a use
            // for, and skips six regexes per scalar.
            let parser = try Parser(yaml: yamlString, resolver: Resolver([.merge]))
            let node = try parser.singleRoot() ?? ""
            return try block(node)
        } catch let error as DecodingError {
            throw error
        } catch {
            let context = DecodingError.Context(
                codingPath: [],
                debugDescription: "The given data was not valid YAML.",
                underlyingError: error
            )
            throw DecodingError.dataCorrupted(context)
        }
    }
}

private struct _YAMLDecoder: Decoder {

    fileprivate let node: Node

    init(referencing node: Node, userInfo: [CodingUserInfoKey: Any], codingPath: [any CodingKey] = []) {
        self.node = node
        self.userInfo = userInfo
        self.codingPath = codingPath
    }

    // MARK: - Swift.Decoder Methods

    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard let mapping = node.mapping?.flatten() else {
            throw _typeMismatch(at: codingPath, expectation: Node.Mapping.self, reality: node)
        }
        return .init(_YAMLKeyedDecodingContainer<Key>(decoder: self, wrapping: mapping))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard let sequence = node.sequence else {
            throw _typeMismatch(at: codingPath, expectation: Node.Sequence.self, reality: node)
        }
        return _YAMLUnkeyedDecodingContainer(decoder: self, wrapping: sequence)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        return self
    }

    // MARK: -

    /// create a new `_YAMLDecoder` instance referencing `node` as `key` inheriting `userInfo`
    func decoder(referencing node: Node, `as` key: any CodingKey) -> _YAMLDecoder {
        return .init(referencing: node, userInfo: userInfo, codingPath: codingPath + [key])
    }

    /// returns the `Node.Scalar` of `node` or throws `DecodingError.typeMismatch`
    fileprivate func scalar() throws -> Node.Scalar {
        switch node {
        case .scalar(let scalar):
            return scalar
        case .mapping(let mapping):
            throw _typeMismatch(at: codingPath, expectation: Node.Scalar.self, reality: mapping)
        case .sequence(let sequence):
            throw _typeMismatch(at: codingPath, expectation: Node.Scalar.self, reality: sequence)
        case .alias(let alias):
            throw _typeMismatch(at: codingPath, expectation: Node.Scalar.self, reality: alias)
        }
    }
}

private struct _YAMLKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {

    private let decoder: _YAMLDecoder
    private let mapping: Node.Mapping

    init(decoder: _YAMLDecoder, wrapping mapping: Node.Mapping) {
        self.decoder = decoder

        // Yams asks `mapping.keys.contains(...)`, which scans; going through the mapping's own
        // lookup keeps this off the hot path, since it runs once per decoded value.
        let decodeAnchor: Anchor?
        let decodeTag: Tag?

        if let anchor = mapping.anchor, mapping.index(forKey: .anchorKeyNode) == nil {
            decodeAnchor = anchor
        } else {
            decodeAnchor = nil
        }

        if mapping.tag.name != .implicit && mapping.index(forKey: .tagKeyNode) == nil {
            decodeTag = mapping.tag
        } else {
            decodeTag = nil
        }

        switch (decodeAnchor, decodeTag) {
        case (nil, nil):
            self.mapping = mapping
        case (let anchor?, nil):
            var mutableMapping = mapping
            mutableMapping[.anchorKeyNode] = .scalar(.init(anchor.rawValue))
            self.mapping = mutableMapping
        case (nil, let tag?):
            var mutableMapping = mapping
            mutableMapping[.tagKeyNode] = .scalar(.init(tag.name.rawValue))
            self.mapping = mutableMapping
        case let (anchor?, tag?):
            var mutableMapping = mapping
            mutableMapping[.anchorKeyNode] = .scalar(.init(anchor.rawValue))
            mutableMapping[.tagKeyNode] = .scalar(.init(tag.name.rawValue))
            self.mapping = mutableMapping
        }
    }

    // MARK: - Swift.KeyedDecodingContainerProtocol Methods

    var codingPath: [any CodingKey] {
        decoder.codingPath
    }

    var allKeys: [Key] {
        mapping.keys
            .filter { $0 != .anchorKeyNode && $0 != .tagKeyNode }
            .compactMap { $0.string.flatMap(Key.init(stringValue:)) }
    }

    func contains(_ key: Key) -> Bool {
        return mapping[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        return try decoder(for: key).decodeNil()
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable & ScalarConstructible {
        return try decoder(for: key).decode(type)
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        return try decoder(for: key).decode(type)
    }

    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        return try decoder(for: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        return try decoder(for: key).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        return try decoder(for: _YAMLCodingKey.super)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        return try decoder(for: key)
    }

    // MARK: -

    private func node(for key: any CodingKey) throws -> Node {
        guard let node = mapping[key.stringValue] else {
            throw _keyNotFound(at: codingPath, key, "No value associated with key \(key) (\"\(key.stringValue)\").")
        }
        return node
    }

    private func decoder(for key: any CodingKey) throws -> _YAMLDecoder {
        decoder.decoder(referencing: try node(for: key), as: key)
    }
}

private struct _YAMLUnkeyedDecodingContainer: UnkeyedDecodingContainer {

    private let decoder: _YAMLDecoder
    private let sequence: Node.Sequence

    init(decoder: _YAMLDecoder, wrapping sequence: Node.Sequence) {
        self.decoder = decoder
        self.sequence = sequence
        self.currentIndex = 0
    }

    // MARK: - Swift.UnkeyedDecodingContainer Methods

    var codingPath: [any CodingKey] {
        decoder.codingPath
    }

    var count: Int? {
        sequence.count
    }

    var isAtEnd: Bool {
        currentIndex >= sequence.count
    }

    var currentIndex: Int

    mutating func decodeNil() throws -> Bool {
        try throwErrorIfAtEnd(Any?.self)
        return try currentDecoder { $0.decodeNil() }
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable & ScalarConstructible {
        return try currentDecoder { try $0.decode(type) }
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        return try currentDecoder { try $0.decode(type) }
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        return try currentDecoder { try $0.container(keyedBy: type) }
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        return try currentDecoder { try $0.unkeyedContainer() }
    }

    mutating func superDecoder() throws -> any Decoder {
        return try currentDecoder { $0 }
    }

    // MARK: -

    private var currentKey: any CodingKey {
        _YAMLCodingKey(index: currentIndex)
    }

    private var currentNode: Node {
        sequence[currentIndex]
    }

    private func throwErrorIfAtEnd<T>(_ type: T.Type) throws {
        if isAtEnd {
            throw _valueNotFound(at: codingPath + [currentKey], type, "Unkeyed container is at end.")
        }
    }

    private mutating func currentDecoder<T>(closure: (_YAMLDecoder) throws -> T) throws -> T {
        try throwErrorIfAtEnd(T.self)
        let decoded: T = try closure(decoder.decoder(referencing: currentNode, as: currentKey))
        currentIndex += 1
        return decoded
    }
}

extension _YAMLDecoder: SingleValueDecodingContainer {

    // MARK: - Swift.SingleValueDecodingContainer Methods

    func decodeNil() -> Bool { return node.null == NSNull() }
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable & ScalarConstructible { return try _decode(type) }
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable { return try _decode(type) }

    // MARK: -

    private func _decode<T: Decodable>(_ type: T.Type) throws -> T {
        if let dereferenced = dereferenceAnchor(type) {
            return dereferenced
        }

        var constructed = try _construct(type)

        if var anchorCoding = constructed as? YAMLAnchorCoding,
           anchorCoding.yamlAnchor == nil,
           let anchor = self.node.anchor {
            anchorCoding.yamlAnchor = anchor
            constructed = anchorCoding as! T // swiftlint:disable:this force_cast
        }

        recordAnchor(constructed)

        return constructed
    }

    private func _construct<T: Decodable>(_ type: T.Type) throws -> T {
        if let constructibleType = type as? ScalarConstructible.Type {
            let scalarConstructed = try constructScalar(constructibleType)
            guard let scalarT = scalarConstructed as? T else {
                throw _typeMismatch(at: codingPath, expectation: type, reality: scalarConstructed)
            }
            return scalarT
        }
        // not scalar constructable, initialize as Decodable
        return try type.init(from: self)
    }

    /// constuct `T` from `node`
    private func constructScalar<T: ScalarConstructible>(_ type: T.Type) throws -> T {
        let scalar = try self.scalar()
        guard let constructed = type.construct(from: scalar) else {
            throw _typeMismatch(at: codingPath, expectation: type, reality: scalar)
        }
        return constructed
    }

    private func dereferenceAnchor<T>(_ type: T.Type) -> T? {
        guard let anchor = self.node.anchor else {
            return nil
        }

        guard let strategy = userInfo[.aliasDereferencingStrategy] as? any AliasDereferencingStrategy else {
            return nil
        }

        guard let existing = strategy[anchor] as? T else {
            return nil
        }

        return existing
    }

    private func recordAnchor<T: Decodable>(_ constructed: T) {
        guard let anchor = self.node.anchor else {
            return
        }

        guard let strategy = userInfo[.aliasDereferencingStrategy] as? any AliasDereferencingStrategy else {
            return
        }

        return strategy[anchor] = constructed
    }
}

// MARK: Decoder.mark

extension Decoder {
    /// The `Mark` for the underlying `Node` that has been decoded.
    public var mark: Mark? {
        return (self as? _YAMLDecoder)?.node.mark
    }
}

// MARK: - ScalarConstructible FixedWidthInteger & SignedInteger Conformance

extension FixedWidthInteger where Self: SignedInteger {
    /// Construct an instance of `Self`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `Self`, if possible.
    ///
    /// - returns: An instance of `Self`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> Self? {
        return Int64.construct(from: scalar).flatMap(Self.init(exactly:))
    }
}

// MARK: - ScalarConstructible FixedWidthInteger & UnsignedInteger Conformance

extension FixedWidthInteger where Self: UnsignedInteger {
    /// Construct an instance of `Self`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `Self`, if possible.
    ///
    /// - returns: An instance of `Self`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> Self? {
        return UInt64.construct(from: scalar).flatMap(Self.init(exactly:))
    }
}

// MARK: - ScalarConstructible Int8 Conformance
extension Int8: ScalarConstructible {}
// MARK: - ScalarConstructible Int16 Conformance
extension Int16: ScalarConstructible {}
// MARK: - ScalarConstructible Int32 Conformance
extension Int32: ScalarConstructible {}
// MARK: - ScalarConstructible UInt8 Conformance
extension UInt8: ScalarConstructible {}
// MARK: - ScalarConstructible UInt16 Conformance
extension UInt16: ScalarConstructible {}
// MARK: - ScalarConstructible UInt32 Conformance
extension UInt32: ScalarConstructible {}

// MARK: - ScalarConstructible Decimal Conformance

extension Decimal: ScalarConstructible {
    /// Construct an instance of `Decimal`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `Decimal`, if possible.
    ///
    /// - returns: An instance of `Decimal`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> Decimal? {
        return Decimal(string: scalar.string)
    }
}

// MARK: - ScalarConstructible URL Conformance

extension URL: ScalarConstructible {
    /// Construct an instance of `URL`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `URL`, if possible.
    ///
    /// - returns: An instance of `URL`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> URL? {
        return URL(string: scalar.string)
    }
}

// MARK: - CodingKey for `_UnkeyedEncodingContainer`, `_UnkeyedDecodingContainer`, `superEncoder` and `superDecoder`

struct _YAMLCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }

    static let `super` = _YAMLCodingKey(stringValue: "super")!
}

// MARK: - DecodingError helpers

private func _keyNotFound(at codingPath: [any CodingKey], _ key: any CodingKey, _ description: String) -> DecodingError {
    let context = DecodingError.Context(codingPath: codingPath, debugDescription: description)
    return.keyNotFound(key, context)
}

private func _valueNotFound(at codingPath: [any CodingKey], _ type: Any.Type, _ description: String) -> DecodingError {
    let context = DecodingError.Context(codingPath: codingPath, debugDescription: description)
    return .valueNotFound(type, context)
}

private func _typeMismatch(at codingPath: [any CodingKey], expectation: Any.Type, reality: Any) -> DecodingError {
    let description = "Expected to decode \(expectation) but found \(type(of: reality)) instead."
    let context = DecodingError.Context(codingPath: codingPath, debugDescription: description)
    return .typeMismatch(expectation, context)
}

// MARK: TopLevelDecoder

#if canImport(Combine)
import protocol Combine.TopLevelDecoder

extension YAMLDecoder: TopLevelDecoder {
    public typealias Input = Data

    public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
        try decode(type, from: data, userInfo: [:])
    }
}
#endif

// MARK: DecodableWithConfiguration

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension YAMLDecoder {

    // MARK: JSONDecoder API

    /// Returns a value of the type you specify, decoded from a YAML object.
    ///
    /// - parameter type:          The type of the value to decode from the supplied YAML object.
    /// - parameter data:          The YAML object `Data` to decode.
    /// - parameter configuration: A decoding configuration that provides additional information necessary for decoding.
    ///
    /// - returns: A value of the specified type, if the decoder can parse the data.
    public func decode<T>(
        _ type: T.Type = T.self,
        from data: Data,
        configuration: T.DecodingConfiguration
    ) throws -> T where T: DecodableWithConfiguration {
        try decode(type, from: data, configuration: configuration, userInfo: [:])
    }

    /// Returns a value of the type you specify, decoded from a YAML object.
    ///
    /// - parameter type:          The type of the value to decode from the supplied YAML object.
    /// - parameter data:          The YAML object `Data` to decode.
    /// - parameter configuration: A configuration instance provider to help decode types that don't support
    ///                            decoding by themselves.
    ///
    /// - returns: A value of the specified type, if the decoder can parse the data.
    public func decode<T: DecodableWithConfiguration, C: DecodingConfigurationProviding>(
        _ type: T.Type = T.self,
        from data: Data,
        configuration: C.Type
    ) throws -> T where T.DecodingConfiguration == C.DecodingConfiguration {
        try decode(type, from: data, configuration: configuration, userInfo: [:])
    }

    // MARK: RapidYAML API

    /// Returns a value of the type you specify, decoded from a YAML object.
    ///
    /// - parameter type:          The type of the value to decode from the supplied YAML object.
    /// - parameter data:          The YAML object `Data` to decode.
    /// - parameter configuration: A decoding configuration that provides additional information necessary for decoding.
    /// - parameter userInfo:      A dictionary you use to customize the decoding process by providing
    ///                            contextual information.
    ///
    /// - returns: A value of the specified type, if the decoder can parse the data.
    public func decode<T>(
        _ type: T.Type = T.self,
        from data: Data,
        configuration: T.DecodingConfiguration,
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> T where T: DecodableWithConfiguration {
        guard let yamlString = String(data: data, encoding: options.encoding) else {
            throw YAMLError.dataCouldNotBeDecoded(encoding: options.encoding)
        }

        return try processNode(type, from: yamlString) { [type, configuration, userInfo] node in
            try self.decode(type, from: node, configuration: configuration, userInfo: userInfo)
        }
    }

    /// Returns a value of the type you specify, decoded from a YAML object.
    ///
    /// - parameter type:          The type of the value to decode from the supplied YAML object.
    /// - parameter data:          The YAML object `Data` to decode.
    /// - parameter configuration: A configuration instance provider to help decode types that don't support
    ///                            decoding by themselves.
    /// - parameter userInfo:      A dictionary you use to customize the decoding process by providing
    ///                            contextual information.
    ///
    /// - returns: A value of the specified type, if the decoder can parse the data.
    public func decode<T: DecodableWithConfiguration, C: DecodingConfigurationProviding>(
        _ type: T.Type = T.self,
        from data: Data,
        configuration: C.Type,
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> T where T.DecodingConfiguration == C.DecodingConfiguration {
        try decode(type, from: data, configuration: configuration.decodingConfiguration, userInfo: userInfo)
    }

    // MARK: Node decoder

    /// Decode a `DecodableWithConfiguration` type from a given `Node` and optional user info mapping.
    ///
    /// - parameter type:          The type of the value to decode from the supplied YAML node.
    /// - parameter node:          YAML Node to decode.
    /// - parameter configuration: A configuration instance that provides additional information necessary
    ///                            for decoding.
    /// - parameter userInfo:      A dictionary you use to customize the decoding process by providing
    ///                            contextual information.
    ///
    /// - returns: Returns the decoded type `T`.
    ///
    /// - throws: `DecodingError` or `YAMLError` if something went wrong while decoding.
    public func decode<T>(
        _ type: T.Type = T.self,
        from node: Node,
        configuration: T.DecodingConfiguration,
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) throws -> T where T: DecodableWithConfiguration {
        let decoder = _decoder(from: node, userInfo: userInfo)
        return try type.init(from: decoder, configuration: configuration)
    }
}
