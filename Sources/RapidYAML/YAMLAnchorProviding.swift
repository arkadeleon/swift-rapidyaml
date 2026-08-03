//
//  YAMLAnchorProviding.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

/// Types that conform to YAMLAnchorProviding and Encodable can optionally dictate the name of
/// a yaml anchor when they are encoded with YAMLEncoder
public protocol YAMLAnchorProviding {
    /// the Anchor to encode with this node or nil
    var yamlAnchor: Anchor? { get }
}

/// YAMLAnchorCoding refines YAMLAnchorProviding.
/// Types that conform to YAMLAnchorCoding and Decodable can decode yaml anchors
/// from source documents into `Anchor` values for reference or modification in memory.
public protocol YAMLAnchorCoding: YAMLAnchorProviding {
    /// the Anchor coded with this node or nil if none is present
    var yamlAnchor: Anchor? { get set }
}

internal extension Node {
    static var anchorKeyNode: Self { .scalar(.init("yamlAnchor")) }
}
