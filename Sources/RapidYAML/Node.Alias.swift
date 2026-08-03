//
//  Node.Alias.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

// MARK: Node+Alias

extension Node {
    /// Alias node.
    public struct Alias {
        /// The anchor for this alias.
        public var anchor: Anchor
        /// This node's tag (its type).
        public var tag: Tag
        /// The location for this node.
        public var mark: Mark?

        /// Create a `Node.Alias` using the specified parameters.
        ///
        /// - parameter anchor: The anchor this alias refers to.
        /// - parameter tag:    This alias' `Tag`.
        /// - parameter mark:   This alias' `Mark`.
        public init(_ anchor: Anchor, _ tag: Tag = .implicit, _ mark: Mark? = nil) {
            self.anchor = anchor
            self.tag = tag
            self.mark = mark
        }
    }
}

extension Node.Alias: Comparable {
    /// :nodoc:
    public static func < (lhs: Node.Alias, rhs: Node.Alias) -> Bool {
        lhs.anchor.rawValue < rhs.anchor.rawValue
    }
}

extension Node.Alias: Equatable {
    /// :nodoc:
    public static func == (lhs: Node.Alias, rhs: Node.Alias) -> Bool {
        lhs.anchor == rhs.anchor
    }
}

extension Node.Alias: Hashable {
    /// :nodoc:
    public func hash(into hasher: inout Hasher) {
        hasher.combine(anchor)
    }
}

extension Node.Alias: TagResolvable {
    static let defaultTagName = Tag.Name.implicit
}
