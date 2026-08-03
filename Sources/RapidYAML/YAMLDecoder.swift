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
        public init(encoding: String.Encoding = .utf8) {
            self.encoding = encoding
        }

        /// String encoding used when decoding from `Data`.
        public var encoding: String.Encoding = .utf8
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
        return _YAMLDecoder(referencing: node, userInfo: userInfo)
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
            let node = try node(from: yamlString)
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

    /// Parses and composes `yamlString`, reporting a parse failure as a `YAMLError` rather than as
    /// the `NSError` produced by the Objective-C++ bridge.
    ///
    /// - parameter yamlString: The YAML object `String` to parse.
    ///
    /// - returns: The root node of the first document.
    ///
    /// - throws: `YAMLError` if the string is not valid YAML.
    private func node(from yamlString: String) throws -> Node {
        guard let node = try Composer.compose(yaml: yamlString) else {
            throw YAMLError.composer(context: nil,
                                     problem: "expected a document",
                                     Mark(line: 1, column: 1),
                                     yaml: yamlString)
        }
        return node
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
        guard let mapping = node.mapping else {
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
        self.mapping = mapping
    }

    // MARK: - Swift.KeyedDecodingContainerProtocol Methods

    var codingPath: [any CodingKey] {
        decoder.codingPath
    }

    var allKeys: [Key] {
        mapping.keys.compactMap({ $0.string.flatMap(Key.init(stringValue:)) })
    }

    func contains(_ key: Key) -> Bool {
        return mapping[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        return try decoder(for: key).decodeNil()
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

    /// - note: Yams asks the `Constructor` here (`node.null == NSNull()`). This is the same test
    ///         spelled out: the resolver recognises ``, `~`, `null`, `Null` and `NULL`, and only a
    ///         plain scalar counts, so `key: 'null'` is the string and not nil. Phase 4 replaces
    ///         this with the constructor call.
    func decodeNil() -> Bool {
        guard let scalar = node.scalar, case .plain = scalar.style else { return false }
        return scalar.resolvedTag.name == .null
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        try construct(type) { Bool($0) }
    }

    func decode(_ type: String.Type) throws -> String {
        try construct(type) { $0 }
    }

    func decode(_ type: Double.Type) throws -> Double {
        try construct(type) { Double($0) }
    }

    func decode(_ type: Float.Type) throws -> Float {
        try construct(type) { Float($0) }
    }

    func decode(_ type: Int.Type) throws -> Int {
        try construct(type) { Int($0) }
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try construct(type) { Int8($0) }
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try construct(type) { Int16($0) }
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try construct(type) { Int32($0) }
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try construct(type) { Int64($0) }
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try construct(type) { UInt($0) }
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try construct(type) { UInt8($0) }
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try construct(type) { UInt16($0) }
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try construct(type) { UInt32($0) }
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try construct(type) { UInt64($0) }
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        try _decode(type)
    }

    // MARK: -

    private func _decode<T: Decodable>(_ type: T.Type) throws -> T {
        // `Decimal` and `URL` are `Decodable` through keyed containers, but YAML represents
        // them as plain scalars, so construct them from the scalar instead.
        switch type {
        case is Decimal.Type:
            return try construct(type) { Decimal(string: $0) as? T }
        case is URL.Type:
            return try construct(type) { URL(string: $0) as? T }
        default:
            return try type.init(from: self)
        }
    }

    /// construct `T` from the scalar of `node`, or throws `DecodingError.typeMismatch`
    private func construct<T>(_ type: T.Type, _ closure: (String) -> T?) throws -> T {
        guard let constructed = closure(try scalar().string) else {
            throw _typeMismatch(at: codingPath, expectation: type, reality: node)
        }
        return constructed
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
