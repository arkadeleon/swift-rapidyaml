//
//  YAMLNode.h
//  YAMLNode
//
//  Created by Leon Li on 2025/6/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Domain of the errors reported by the underlying rapidyaml library.
extern NSErrorDomain const YAMLNodeErrorDomain;

typedef NS_ERROR_ENUM(YAMLNodeErrorDomain, YAMLNodeErrorCode) {
    /// A general error, not tied to a location in the YAML source.
    YAMLNodeErrorCodeBasic = 1,
    /// The YAML source is malformed. The location keys below point at the offending token.
    YAMLNodeErrorCodeParse = 2,
    /// An error raised while visiting an already parsed tree.
    YAMLNodeErrorCodeVisit = 3,
};

/// One-based line in the YAML source where the error was detected, as an `NSNumber`.
///
/// Only present on `YAMLNodeErrorCodeParse` errors.
extern NSErrorUserInfoKey const YAMLNodeErrorLineKey;

/// One-based column in the YAML source where the error was detected, as an `NSNumber`.
///
/// Only present on `YAMLNodeErrorCodeParse` errors.
extern NSErrorUserInfoKey const YAMLNodeErrorColumnKey;

/// One-based byte offset into the YAML source where the error was detected, as an `NSNumber`.
///
/// Only present on `YAMLNodeErrorCodeParse` errors.
extern NSErrorUserInfoKey const YAMLNodeErrorOffsetKey;

typedef NS_ENUM(NSInteger, YAMLNodeKind) {
    YAMLNodeKindUnknown = 0,
    /// The root of a multi-document source.
    YAMLNodeKindStream,
    /// One document of a stream.
    YAMLNodeKindDocument,
    YAMLNodeKindMapping,
    YAMLNodeKindSequence,
    YAMLNodeKindScalar,
} NS_SWIFT_NAME(YAMLNode.Kind);

/// How a scalar was written in the source.
typedef NS_ENUM(NSInteger, YAMLScalarStyle) {
    YAMLScalarStyleAny = 0,
    YAMLScalarStylePlain,
    YAMLScalarStyleSingleQuoted,
    YAMLScalarStyleDoubleQuoted,
    YAMLScalarStyleLiteral,
    YAMLScalarStyleFolded,
} NS_SWIFT_NAME(YAMLNode.ScalarStyle);

/// How a mapping or sequence was written in the source.
typedef NS_ENUM(NSInteger, YAMLCollectionStyle) {
    YAMLCollectionStyleAny = 0,
    YAMLCollectionStyleBlock,
    YAMLCollectionStyleFlow,
} NS_SWIFT_NAME(YAMLNode.CollectionStyle);

/// One node of a parsed rapidyaml tree, deep-copied into Foundation types.
///
/// This is a bridging layer only: `RapidYAML.Node` is the public model, and is composed from these
/// in a single pass. rapidyaml stores a key and a value on the same node, so a child of a mapping
/// carries both halves of the pair — the `key`-prefixed properties describe one `Node` and the
/// `value`-prefixed ones the other.
@interface YAMLNode : NSObject

@property (nonatomic, readonly) YAMLNodeKind kind;

/// Children in source order. A mapping's children are its pairs, in the order they were written.
@property (nonatomic, readonly, copy) NSArray<YAMLNode *> *children;

/// Whether this node has a key, i.e. whether it is a child of a mapping.
@property (nonatomic, readonly) BOOL hasKey;
@property (nonatomic, readonly, copy, nullable) NSString *key;
@property (nonatomic, readonly, copy, nullable) NSString *keyTag;
@property (nonatomic, readonly, copy, nullable) NSString *keyAnchor;
/// The anchor this node's key refers to, if the key is an alias (`*anchor: value`).
@property (nonatomic, readonly, copy, nullable) NSString *keyAlias;
@property (nonatomic, readonly) YAMLScalarStyle keyStyle;
/// One-based line of this node's key in the source, or 0 if unknown.
@property (nonatomic, readonly) NSUInteger keyLine;
/// One-based column of this node's key, counted in UTF-8 bytes, or 0 if unknown.
@property (nonatomic, readonly) NSUInteger keyColumn;

/// The scalar value, or `nil` if this node is a container or an empty value.
@property (nonatomic, readonly, copy, nullable) NSString *value;
@property (nonatomic, readonly, copy, nullable) NSString *valueTag;
@property (nonatomic, readonly, copy, nullable) NSString *valueAnchor;
/// The anchor this node's value refers to, if the value is an alias (`key: *anchor`).
@property (nonatomic, readonly, copy, nullable) NSString *valueAlias;
@property (nonatomic, readonly) YAMLScalarStyle valueStyle;
/// One-based line of this node's value in the source, or 0 if unknown.
///
/// A container has no scalar of its own to point at, so it reports the position of its first
/// child rather than of its opening token.
@property (nonatomic, readonly) NSUInteger valueLine;
/// One-based column of this node's value, counted in UTF-8 bytes, or 0 if unknown.
@property (nonatomic, readonly) NSUInteger valueColumn;

@property (nonatomic, readonly) YAMLCollectionStyle collectionStyle;

- (instancetype)init NS_UNAVAILABLE;

/// Parses `yamlString` and returns the root node of the resulting tree.
///
/// Returns `nil` and populates `error` with a `YAMLNodeErrorDomain` error if the source
/// could not be parsed.
- (nullable instancetype)initWithYAMLString:(NSString *)yamlString error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
