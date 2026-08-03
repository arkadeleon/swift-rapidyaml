//
//  YAMLNode.m
//  YAMLNode
//
//  Created by Leon Li on 2025/6/12.
//

#import "YAMLNode.h"
#import "ryml/ryml.hpp"

static NSString * _Nullable NSStringFromSubstr(c4::csubstr substr) {
    if (substr.str == nullptr) {
        return nil;
    }

    NSData *data = [[NSData alloc] initWithBytes:substr.str length:substr.len];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string;
}

static YAMLNodeKind YAMLNodeKindFromNode(ryml::ConstNodeRef node) {
    if (node.is_stream()) {
        return YAMLNodeKindStream;
    }
    if (node.is_doc()) {
        return YAMLNodeKindDocument;
    }
    if (node.is_map()) {
        return YAMLNodeKindMapping;
    }
    if (node.is_seq()) {
        return YAMLNodeKindSequence;
    }
    if (node.has_val()) {
        return YAMLNodeKindScalar;
    }
    return YAMLNodeKindUnknown;
}

@implementation YAMLNode

- (instancetype)initWithYAMLString:(NSString *)yamlString {
    ryml::Tree tree = ryml::parse_in_arena([yamlString UTF8String]);
    return [self initWithNode:tree.rootref() parent:nil];
}

- (instancetype)initWithNode:(ryml::ConstNodeRef)node parent:(nullable YAMLNode *)parent {
    self = [super init];
    if (self) {
        _parent = parent;
        _kind = YAMLNodeKindFromNode(node);
        _typeBits = static_cast<uint32_t>(node.type().m_bits);
        _typeString = [NSString stringWithUTF8String:node.type().type_str()];

        _isStream = node.is_stream();
        _isDoc = node.is_doc();
        _isMap = node.is_map();
        _isSeq = node.is_seq();
        _isContainer = node.is_container();
        _hasKey = node.has_key();
        _hasValue = node.has_val();
        _isNull = node.has_val() && node.val_is_null();
        _isRef = node.is_ref();
        _hasAnchor = node.has_anchor();

        if (node.has_key()) {
            _key = NSStringFromSubstr(node.key());
        }
        if (node.has_val()) {
            _value = NSStringFromSubstr(node.val());
        }
        if (node.has_key_tag()) {
            _keyTag = NSStringFromSubstr(node.key_tag());
        }
        if (node.has_val_tag()) {
            _valueTag = NSStringFromSubstr(node.val_tag());
        }
        if (node.has_key_anchor()) {
            _keyAnchor = NSStringFromSubstr(node.key_anchor());
        }
        if (node.has_val_anchor()) {
            _valueAnchor = NSStringFromSubstr(node.val_anchor());
        }
        if (node.is_key_ref()) {
            _keyReference = NSStringFromSubstr(node.key_ref());
        }
        if (node.is_val_ref()) {
            _valueReference = NSStringFromSubstr(node.val_ref());
        }

        NSMutableArray<YAMLNode *> *children = [NSMutableArray array];
        size_t childCount = node.num_children();
        for (size_t pos = 0; pos < childCount; pos++) {
            auto child = node.child(pos);
            YAMLNode *childNode = [[YAMLNode alloc] initWithNode:child parent:self];
            [children addObject:childNode];
        }
        _children = [children copy];
        _childCount = _children.count;

        if (node.is_map()) {
            NSMutableDictionary<NSString *, YAMLNode *> *mapping = [NSMutableDictionary dictionary];
            for (YAMLNode *child in _children) {
                if (child.key != nil) {
                    mapping[child.key] = child;
                }
            }
            _mapping = [mapping copy];
        }

        if (node.is_seq()) {
            _sequence = _children;
        }

        if (!node.is_container() && node.has_val() && !node.val_is_null()) {
            _scalar = NSStringFromSubstr(node.val());
        }

        if (_children == nil) {
            _children = @[];
        }
    }
    return self;
}

- (nullable YAMLNode *)childAtIndex:(NSUInteger)index {
    if (index >= self.children.count) {
        return nil;
    }
    return self.children[index];
}

- (nullable YAMLNode *)childForKey:(NSString *)key {
    for (YAMLNode *child in self.children) {
        if ([child.key isEqualToString:key]) {
            return child;
        }
    }
    return nil;
}

@end
