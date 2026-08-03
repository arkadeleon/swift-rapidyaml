//
//  YAMLNode.m
//  YAMLNode
//
//  Created by Leon Li on 2025/6/12.
//

#import "YAMLNode.h"
#import "ryml/ryml.hpp"

#include <string>

NSErrorDomain const YAMLNodeErrorDomain = @"YAMLNodeErrorDomain";

NSErrorUserInfoKey const YAMLNodeErrorLineKey = @"YAMLNodeErrorLine";
NSErrorUserInfoKey const YAMLNodeErrorColumnKey = @"YAMLNodeErrorColumn";
NSErrorUserInfoKey const YAMLNodeErrorOffsetKey = @"YAMLNodeErrorOffset";

namespace {

/// The exception thrown by the error callbacks installed below.
///
/// rapidyaml's error callbacks must not return: if one does, the caller may loop forever or
/// crash. The library's own default callbacks call `abort()`, which would take the whole
/// process down on malformed input, so they are replaced with callbacks that throw this.
struct YAMLNodeException {
    YAMLNodeErrorCode code;
    std::string message;
    /// Location in the YAML source. Only meaningful for parse errors; the other error kinds
    /// only carry a location in the rapidyaml C++ source, which is of no use to a caller.
    bool hasLocation;
    size_t offset;
    size_t line;
    size_t col;
};

[[noreturn]] void ThrowBasicError(c4::csubstr msg, ryml::ErrorDataBasic const&, void *) {
    throw YAMLNodeException{YAMLNodeErrorCodeBasic, std::string(msg.str, msg.len), false, 0, 0, 0};
}

[[noreturn]] void ThrowParseError(c4::csubstr msg, ryml::ErrorDataParse const& errdata, void *) {
    ryml::Location const& loc = errdata.ymlloc;
    throw YAMLNodeException{
        YAMLNodeErrorCodeParse,
        std::string(msg.str, msg.len),
        static_cast<bool>(loc),
        loc.offset,
        loc.line,
        loc.col,
    };
}

[[noreturn]] void ThrowVisitError(c4::csubstr msg, ryml::ErrorDataVisit const&, void *) {
    throw YAMLNodeException{YAMLNodeErrorCodeVisit, std::string(msg.str, msg.len), false, 0, 0, 0};
}

/// Installs the throwing error callbacks. rapidyaml keeps them in global state, and objects
/// copy them from there at construction time, so this must run before the first parse.
void InstallThrowingErrorCallbacks() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ryml::Callbacks callbacks;
        callbacks.set_error_basic(ThrowBasicError);
        callbacks.set_error_parse(ThrowParseError);
        callbacks.set_error_visit(ThrowVisitError);
        ryml::set_callbacks(callbacks);
    });
}

NSError *NSErrorFromException(YAMLNodeException const& exception) {
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];

    NSString *message = [[NSString alloc] initWithBytes:exception.message.data()
                                                 length:exception.message.size()
                                               encoding:NSUTF8StringEncoding];
    if (message != nil) {
        userInfo[NSLocalizedDescriptionKey] = message;
    }

    if (exception.hasLocation) {
        if (exception.offset != ryml::npos) {
            userInfo[YAMLNodeErrorOffsetKey] = @(exception.offset);
        }
        if (exception.line != ryml::npos) {
            userInfo[YAMLNodeErrorLineKey] = @(exception.line);
        }
        if (exception.col != ryml::npos) {
            userInfo[YAMLNodeErrorColumnKey] = @(exception.col);
        }
    }

    return [NSError errorWithDomain:YAMLNodeErrorDomain code:exception.code userInfo:userInfo];
}

}

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

- (nullable instancetype)initWithYAMLString:(NSString *)yamlString error:(NSError **)error {
    InstallThrowingErrorCallbacks();

    try {
        ryml::Tree tree = ryml::parse_in_arena([yamlString UTF8String]);
        return [self initWithNode:tree.rootref() parent:nil];
    } catch (YAMLNodeException const& exception) {
        if (error != NULL) {
            *error = NSErrorFromException(exception);
        }
        return nil;
    }
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
