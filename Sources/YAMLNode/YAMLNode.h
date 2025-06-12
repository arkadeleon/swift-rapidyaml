//
//  YAMLNode.h
//  YAMLNode
//
//  Created by Leon Li on 2025/6/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YAMLNode : NSObject

@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, YAMLNode *> *mapping;
@property (nonatomic, readonly, copy, nullable) NSArray<YAMLNode *> *sequence;
@property (nonatomic, readonly, copy, nullable) NSString *scalar;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithYAMLString:(NSString *)yamlString;

@end

NS_ASSUME_NONNULL_END
