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

/// Converts a tag as written into its long form, so that `!!str` and `!<tag:yaml.org,2002:str>`
/// both arrive in Swift as `tag:yaml.org,2002:str` — the form libyaml hands to Yams. Tags that are
/// not from the YAML schema, such as `!foo`, are passed through unchanged.
static NSString * _Nullable NSStringFromTag(c4::csubstr tag) {
    if (tag.str == nullptr) {
        return nil;
    }

    c4::csubstr normalized = ryml::normalize_tag_long(tag);
    if (normalized.len >= 2 && normalized.begins_with('<') && normalized.ends_with('>')) {
        normalized = normalized.range(1, normalized.len - 1);
    }
    return NSStringFromSubstr(normalized);
}

static YAMLNodeKind YAMLNodeKindFromNode(ryml::ConstNodeRef node) {
    // A document node also carries the type of its contents — `---\na: 1` is a DOCMAP — so the
    // container checks have to come before the document check.
    if (node.is_stream()) {
        return YAMLNodeKindStream;
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
    if (node.is_doc()) {
        return YAMLNodeKindDocument;
    }
    return YAMLNodeKindUnknown;
}

static YAMLScalarStyle YAMLKeyStyleFromNode(ryml::ConstNodeRef node) {
    if (!node.has_key()) {
        return YAMLScalarStyleAny;
    }
    if (node.is_key_literal()) {
        return YAMLScalarStyleLiteral;
    }
    if (node.is_key_folded()) {
        return YAMLScalarStyleFolded;
    }
    if (node.is_key_squo()) {
        return YAMLScalarStyleSingleQuoted;
    }
    if (node.is_key_dquo()) {
        return YAMLScalarStyleDoubleQuoted;
    }
    if (node.is_key_plain()) {
        return YAMLScalarStylePlain;
    }
    return YAMLScalarStyleAny;
}

static YAMLScalarStyle YAMLValueStyleFromNode(ryml::ConstNodeRef node) {
    if (!node.has_val()) {
        return YAMLScalarStyleAny;
    }
    if (node.is_val_literal()) {
        return YAMLScalarStyleLiteral;
    }
    if (node.is_val_folded()) {
        return YAMLScalarStyleFolded;
    }
    if (node.is_val_squo()) {
        return YAMLScalarStyleSingleQuoted;
    }
    if (node.is_val_dquo()) {
        return YAMLScalarStyleDoubleQuoted;
    }
    if (node.is_val_plain()) {
        return YAMLScalarStylePlain;
    }
    return YAMLScalarStyleAny;
}

static YAMLCollectionStyle YAMLCollectionStyleFromNode(ryml::ConstNodeRef node) {
    if (!node.is_container()) {
        return YAMLCollectionStyleAny;
    }
    if (node.type().is_flow()) {
        return YAMLCollectionStyleFlow;
    }
    if (node.type().is_block()) {
        return YAMLCollectionStyleBlock;
    }
    return YAMLCollectionStyleAny;
}

/// Resolves the one-based line and column of `scalar` in the parsed source.
///
/// `Tree::location()` would do this, but it assumes every scalar still points into the source
/// buffer. Scalars that had to be filtered — some escapes, and block scalars that grow — are
/// relocated into the tree's arena, and looking those up trips a check inside rapidyaml. Only
/// scalars that really are substrings of the source get a location; the rest report 0.
static void YAMLLocationOfScalar(c4::csubstr scalar, ryml::Parser const& parser, NSUInteger *line, NSUInteger *column) {
    *line = 0;
    *column = 0;

    if (scalar.str == nullptr || !scalar.is_sub(parser.source())) {
        return;
    }

    ryml::Location location = parser.val_location(scalar.str);
    if (location.line != ryml::npos) {
        *line = location.line + 1;
    }
    if (location.col != ryml::npos) {
        *column = location.col + 1;
    }
}

@interface YAMLNode ()

- (instancetype)initWithNode:(ryml::ConstNodeRef)node parser:(ryml::Parser const&)parser;

@end

@implementation YAMLNode

- (nullable instancetype)initWithYAMLString:(NSString *)yamlString error:(NSError **)error {
    InstallThrowingErrorCallbacks();

    try {
        // Locations are opt-in because tracking them costs an extra pass over the source. `Mark`
        // is part of the public model, so they are always on.
        ryml::EventHandlerTree eventHandler = {};
        ryml::Parser parser(&eventHandler, ryml::ParserOptions().locations(true));
        ryml::Tree tree = ryml::parse_in_arena(&parser, [yamlString UTF8String]);
        return [self initWithNode:tree.rootref() parser:parser];
    } catch (YAMLNodeException const& exception) {
        if (error != NULL) {
            *error = NSErrorFromException(exception);
        }
        return nil;
    }
}

- (instancetype)initWithNode:(ryml::ConstNodeRef)node parser:(ryml::Parser const&)parser {
    self = [super init];
    if (self) {
        _kind = YAMLNodeKindFromNode(node);
        _collectionStyle = YAMLCollectionStyleFromNode(node);

        _hasKey = node.has_key();
        if (node.has_key()) {
            _key = NSStringFromSubstr(node.key());
            _keyStyle = YAMLKeyStyleFromNode(node);
            YAMLLocationOfScalar(node.key(), parser, &_keyLine, &_keyColumn);
        }
        if (node.has_key_tag()) {
            _keyTag = NSStringFromTag(node.key_tag());
        }
        if (node.has_key_anchor()) {
            _keyAnchor = NSStringFromSubstr(node.key_anchor());
        }
        if (node.is_key_ref()) {
            _keyAlias = NSStringFromSubstr(node.key_ref());
        }

        if (node.has_val()) {
            _value = NSStringFromSubstr(node.val());
            _valueStyle = YAMLValueStyleFromNode(node);
            YAMLLocationOfScalar(node.val(), parser, &_valueLine, &_valueColumn);
        }
        if (node.has_val_tag()) {
            _valueTag = NSStringFromTag(node.val_tag());
        }
        if (node.has_val_anchor()) {
            _valueAnchor = NSStringFromSubstr(node.val_anchor());
        }
        if (node.is_val_ref()) {
            _valueAlias = NSStringFromSubstr(node.val_ref());
        }

        NSMutableArray<YAMLNode *> *children = [NSMutableArray arrayWithCapacity:node.num_children()];
        for (ryml::ConstNodeRef child : node.children()) {
            [children addObject:[[YAMLNode alloc] initWithNode:child parser:parser]];
        }
        _children = [children copy];

        // A container has no scalar to point at, so stand in the position of its first child.
        if (_valueLine == 0 && _children.count > 0) {
            YAMLNode *first = _children.firstObject;
            _valueLine = first.hasKey ? first.keyLine : first.valueLine;
            _valueColumn = first.hasKey ? first.keyColumn : first.valueColumn;
        }
    }
    return self;
}

@end
