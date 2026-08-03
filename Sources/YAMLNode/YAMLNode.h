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

/// Zero-based byte offset into the YAML source where the error was detected, as an `NSNumber`.
///
/// Only present on `YAMLNodeErrorCodeParse` errors.
extern NSErrorUserInfoKey const YAMLNodeErrorOffsetKey;

typedef NS_ENUM(NSInteger, YAMLNodeKind) {
    YAMLNodeKindUnknown = 0,
    YAMLNodeKindStream,
    YAMLNodeKindDocument,
    YAMLNodeKindMapping,
    YAMLNodeKindSequence,
    YAMLNodeKindScalar,
} NS_SWIFT_NAME(YAMLNode.Kind);

@interface YAMLNode : NSObject

@property (nonatomic, readonly) YAMLNodeKind kind;
@property (nonatomic, readonly) uint32_t typeBits;
@property (nonatomic, readonly, copy) NSString *typeString;

@property (nonatomic, readonly) BOOL isStream;
@property (nonatomic, readonly) BOOL isDoc;
@property (nonatomic, readonly) BOOL isMap;
@property (nonatomic, readonly) BOOL isSeq;
@property (nonatomic, readonly) BOOL isContainer;
@property (nonatomic, readonly) BOOL hasKey;
@property (nonatomic, readonly) BOOL hasValue;
@property (nonatomic, readonly) BOOL isNull;
@property (nonatomic, readonly) BOOL isRef;
@property (nonatomic, readonly) BOOL hasAnchor;

@property (nonatomic, readonly, copy, nullable) NSString *key;
@property (nonatomic, readonly, copy, nullable) NSString *value;
@property (nonatomic, readonly, copy, nullable) NSString *keyTag;
@property (nonatomic, readonly, copy, nullable) NSString *valueTag;
@property (nonatomic, readonly, copy, nullable) NSString *keyAnchor;
@property (nonatomic, readonly, copy, nullable) NSString *valueAnchor;
@property (nonatomic, readonly, copy, nullable) NSString *keyReference;
@property (nonatomic, readonly, copy, nullable) NSString *valueReference;

@property (nonatomic, readonly, weak, nullable) YAMLNode *parent;
@property (nonatomic, readonly, copy) NSArray<YAMLNode *> *children;
@property (nonatomic, readonly) NSUInteger childCount;

@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, YAMLNode *> *mapping;
@property (nonatomic, readonly, copy, nullable) NSArray<YAMLNode *> *sequence;
@property (nonatomic, readonly, copy, nullable) NSString *scalar;

- (instancetype)init NS_UNAVAILABLE;

/// Parses `yamlString` and returns the root node of the resulting tree.
///
/// Returns `nil` and populates `error` with a `YAMLNodeErrorDomain` error if the source
/// could not be parsed.
- (nullable instancetype)initWithYAMLString:(NSString *)yamlString error:(NSError **)error;

- (nullable YAMLNode *)childAtIndex:(NSUInteger)index NS_SWIFT_NAME(child(at:));
- (nullable YAMLNode *)childForKey:(NSString *)key NS_SWIFT_NAME(child(forKey:));

@end

NS_ASSUME_NONNULL_END
