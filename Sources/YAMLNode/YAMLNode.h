//
//  YAMLNode.h
//  YAMLNode
//
//  Created by Leon Li on 2025/6/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
- (instancetype)initWithYAMLString:(NSString *)yamlString;

- (nullable YAMLNode *)childAtIndex:(NSUInteger)index NS_SWIFT_NAME(child(at:));
- (nullable YAMLNode *)childForKey:(NSString *)key NS_SWIFT_NAME(child(forKey:));

@end

NS_ASSUME_NONNULL_END
