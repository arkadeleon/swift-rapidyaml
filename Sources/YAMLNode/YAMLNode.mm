//
//  YAMLNode.m
//  YAMLNode
//
//  Created by Leon Li on 2025/6/12.
//

#import "YAMLNode.h"
#import "ryml/ryml.hpp"

NSString *NSStringFromSubstr(c4::csubstr substr) {
    NSData *data = [[NSData alloc] initWithBytes:substr.str length:substr.len];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string;
}

@implementation YAMLNode

- (instancetype)initWithYAMLString:(NSString *)yamlString {
    ryml::Tree tree = ryml::parse_in_arena([yamlString UTF8String]);
    return [self initWithNode:tree.rootref()];
}

- (instancetype)initWithNode:(ryml::NodeRef)node {
    self = [super init];
    if (self) {
        if (node.is_map()) {
            NSMutableDictionary<NSString *, YAMLNode *> *mapping = [NSMutableDictionary dictionary];
            size_t childCount = node.num_children();
            for (size_t pos = 0; pos < childCount; pos++) {
                auto child = node.child(pos);
                NSString *key = NSStringFromSubstr(child.key());
                mapping[key] = [[YAMLNode alloc] initWithNode:child];
            }
            _mapping = [mapping copy];
        } else if (node.is_seq()) {
            NSMutableArray<YAMLNode *> *sequence = [NSMutableArray array];
            size_t childCount = node.num_children();
            for (size_t pos = 0; pos < childCount; pos++) {
                auto child = node.child(pos);
                YAMLNode *childNode = [[YAMLNode alloc] initWithNode:child];
                [sequence addObject:childNode];
            }
            _sequence = [sequence copy];
        } else if (node.is_keyval() && !node.val_is_null()) {
            _scalar = NSStringFromSubstr(node.val());
        }
    }
    return self;
}

@end
