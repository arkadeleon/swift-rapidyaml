//
//  ParsedTree.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
internal import YAMLNode

/// A parsed rapidyaml tree, held for as long as anything reads from it.
///
/// Every scalar a `YAMLNodeRecord` reports points into the tree's arena, so the tree has to
/// outlive composition. Owning it in a class ties that to the composer's lifetime.
final class ParsedTree {

    private let handle: OpaquePointer

    /// Parses `yaml`.
    ///
    /// - throws: `YAMLError` if the source is not valid YAML.
    init(yaml: String) throws {
        var source = yaml
        var failure: NSError?
        let handle: OpaquePointer? = source.withUTF8 { bytes in
            bytes.withMemoryRebound(to: CChar.self) { chars in
                guard let base = chars.baseAddress else { return nil as OpaquePointer? }
                return YAMLTreeParse(base, chars.count, &failure)
            }
        }

        if let failure {
            // The bridge reports failures as an NSError; YAMLError is what callers expect.
            throw YAMLError(from: failure, with: yaml)
        }
        guard let handle else {
            throw YAMLError.reader(problem: "the tree could not be parsed", offset: nil, value: -1, yaml: yaml)
        }
        self.handle = handle
    }

    deinit {
        YAMLTreeFree(handle)
    }

    /// The node the whole source hangs from.
    var root: YAMLNodeID {
        return YAMLTreeRoot(handle)
    }

    /// Everything about `node`, read in one call.
    func read(_ node: YAMLNodeID) -> YAMLNodeRecord {
        var record = YAMLNodeRecord()
        YAMLTreeRead(handle, node, &record)
        return record
    }

    /// The first child of `node`, or `nil` if it has none.
    func firstChild(of node: YAMLNodeID) -> YAMLNodeID? {
        let child = YAMLTreeFirstChild(handle, node)
        return child == YAMLTreeNoNode ? nil : child
    }

    /// The sibling after `node`, or `nil` if it is the last.
    func nextSibling(of node: YAMLNodeID) -> YAMLNodeID? {
        let sibling = YAMLTreeNextSibling(handle, node)
        return sibling == YAMLTreeNoNode ? nil : sibling
    }
}

extension YAMLStringRef {
    /// The slice as a `String`, or `nil` when the property is absent.
    ///
    /// This is where the old bridge spent much of its time: it built an `NSString` per scalar and
    /// Swift then copied it again. Decoding UTF-8 straight out of the arena skips both.
    var string: String? {
        guard let bytes else { return nil }
        return bytes.withMemoryRebound(to: UInt8.self, capacity: length) {
            String(decoding: UnsafeBufferPointer(start: $0, count: length), as: UTF8.self)
        }
    }
}
