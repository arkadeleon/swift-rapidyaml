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
};

/// How a scalar was written in the source.
typedef NS_ENUM(NSInteger, YAMLScalarStyle) {
    YAMLScalarStyleAny = 0,
    YAMLScalarStylePlain,
    YAMLScalarStyleSingleQuoted,
    YAMLScalarStyleDoubleQuoted,
    YAMLScalarStyleLiteral,
    YAMLScalarStyleFolded,
};

/// How a mapping or sequence was written in the source.
typedef NS_ENUM(NSInteger, YAMLCollectionStyle) {
    YAMLCollectionStyleAny = 0,
    YAMLCollectionStyleBlock,
    YAMLCollectionStyleFlow,
};

/// A parsed rapidyaml tree, kept alive so that Swift can walk it in place.
///
/// The tree used to be copied into an Objective-C object graph before `RapidYAML.Node` was built
/// from it, which meant an object and a pair of `NSString`s per node that nothing outlived the
/// composition. Instead the tree stays where rapidyaml put it and this exposes a reader over it:
/// scalars come back as pointers into the tree's own arena, which Swift turns into `String`
/// directly, and nothing in between is allocated.
///
/// Every pointer handed out stays valid until `YAMLTreeFree`.
///
/// The reader below is plain C rather than Objective-C: it is called once per node, and a message
/// send per property is exactly the cost this exists to avoid.
#if defined(__cplusplus)
extern "C" {
#endif

typedef struct YAMLTree YAMLTree;

/// A node's position in the tree. `YAMLTreeNoNode` is the absence of one.
typedef size_t YAMLNodeID;

extern const YAMLNodeID YAMLTreeNoNode;

/// A slice of the tree's arena, or `bytes == NULL` when the property is absent.
///
/// Not NUL-terminated: `length` is the whole of it.
typedef struct {
    const char * _Nullable bytes;
    size_t length;
} YAMLStringRef;

/// Everything about one node, filled in a single call so that walking a tree does not cost a
/// function call per property.
///
/// rapidyaml stores a key and a value on the same node, so a child of a mapping carries both
/// halves of the pair — the `key`-prefixed fields describe one `Node` and the `value`-prefixed
/// ones the other. A line or column of 0 means the position is unknown.
typedef struct {
    YAMLNodeKind kind;
    size_t childCount;

    bool hasKey;
    YAMLStringRef key;
    YAMLStringRef keyTag;
    YAMLStringRef keyAnchor;
    /// The anchor this node's key refers to, if the key is an alias (`*anchor: value`).
    YAMLStringRef keyAlias;
    YAMLScalarStyle keyStyle;
    size_t keyLine;
    size_t keyColumn;

    YAMLStringRef value;
    YAMLStringRef valueTag;
    YAMLStringRef valueAnchor;
    /// The anchor this node's value refers to, if the value is an alias (`key: *anchor`).
    YAMLStringRef valueAlias;
    YAMLScalarStyle valueStyle;
    /// A container has no scalar of its own to point at, so it reports the position of its first
    /// child rather than of its opening token.
    size_t valueLine;
    size_t valueColumn;

    YAMLCollectionStyle collectionStyle;
} YAMLNodeRecord;

/// Parses `yaml` and returns a tree to read it from, or NULL on failure.
///
/// - parameter yaml:   UTF-8 bytes. Copied, so the caller need not keep them.
/// - parameter length: How many bytes of `yaml` to read.
/// - parameter error:  Set to a `YAMLNodeErrorDomain` error when the source cannot be parsed.
YAMLTree * _Nullable YAMLTreeParse(const char *yaml, size_t length, NSError **error);

/// Releases a tree and everything read out of it.
void YAMLTreeFree(YAMLTree * _Nullable tree);

/// The node the whole source hangs from.
YAMLNodeID YAMLTreeRoot(const YAMLTree *tree);

/// Fills `record` with everything about `node`.
void YAMLTreeRead(const YAMLTree *tree, YAMLNodeID node, YAMLNodeRecord *record);

/// The first child of `node`, or `YAMLTreeNoNode` if it has none.
///
/// Children are a linked list in rapidyaml, so they are walked with `YAMLTreeNextSibling` rather
/// than indexed — asking for the `i`th would restart the walk every time.
YAMLNodeID YAMLTreeFirstChild(const YAMLTree *tree, YAMLNodeID node);

/// The sibling after `node`, or `YAMLTreeNoNode` if it is the last.
YAMLNodeID YAMLTreeNextSibling(const YAMLTree *tree, YAMLNodeID node);

#if defined(__cplusplus)
}
#endif

/// One node of a tree to be emitted.
///
/// rapidyaml emits a tree rather than an event stream, so the whole document is described up
/// front and handed to `YAMLEmitter` in one call.
@interface YAMLEmitterNode : NSObject

@property (nonatomic) YAMLNodeKind kind;

@property (nonatomic, copy, nullable) NSString *key;
@property (nonatomic, copy, nullable) NSString *keyTag;
@property (nonatomic, copy, nullable) NSString *keyAnchor;
@property (nonatomic) YAMLScalarStyle keyStyle;

@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic, copy, nullable) NSString *valueTag;
@property (nonatomic, copy, nullable) NSString *valueAnchor;
/// The anchor this node aliases. A node is either an alias or a value, never both.
@property (nonatomic, copy, nullable) NSString *valueAlias;
@property (nonatomic) YAMLScalarStyle valueStyle;

@property (nonatomic) YAMLCollectionStyle collectionStyle;

/// Children in the order they should be emitted. A mapping's children are its pairs.
@property (nonatomic, copy) NSArray<YAMLEmitterNode *> *children;

@end

/// Emits YAML from trees built out of `YAMLEmitterNode`.
@interface YAMLEmitter : NSObject

/// Emits `documents` as a single YAML stream.
///
/// Returns `nil` and populates `error` with a `YAMLNodeErrorDomain` error if the tree could not
/// be emitted.
///
/// - parameter documents:     The documents to emit, in order.
/// - parameter explicitStart: Whether to write a `---` marker before each document. A stream of
///                            more than one document always gets markers, whatever this says.
+ (nullable NSString *)emitDocuments:(NSArray<YAMLEmitterNode *> *)documents
                       explicitStart:(BOOL)explicitStart
                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
