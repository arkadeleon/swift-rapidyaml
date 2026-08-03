//
//  YAMLTagProviding.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

/// Types that conform to YAMLTagProviding and Encodable can optionally dictate the name of
/// a yaml tag when they are encoded with YAMLEncoder
public protocol YAMLTagProviding {
    /// the Tag to encode with this node or nil
    var yamlTag: Tag? { get }
}

/// YAMLTagCoding refines YAMLTagProviding.
/// Types that conform to YAMLTagCoding and Decodable can decode yaml tags
/// from source documents into `Tag` values for reference or modification in memory.
public protocol YAMLTagCoding: YAMLTagProviding {
    /// the Tag coded with this node or nil if none is present
    var yamlTag: Tag? { get set }
}

internal extension Node {
    static var tagKeyNode: Self { .scalar(.init("yamlTag")) }
}
