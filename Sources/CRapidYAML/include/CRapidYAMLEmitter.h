//
//  CRapidYAMLEmitter.h
//  CRapidYAML
//
//  Created by Leon Li on 2025/6/12.
//

#import <Foundation/Foundation.h>

#import "CRapidYAMLTree.h"

NS_ASSUME_NONNULL_BEGIN

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
/// Returns `nil` and populates `error` with a `CRapidYAMLErrorDomain` error if the tree could not
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
