//
//  Emitter.mm
//  CRapidYAML
//
//  Created by Leon Li on 2025/6/12.
//

#import "include/CRapidYAMLEmitter.h"
#import "Internal.h"

namespace {

/// Copies `string` into the tree's arena, so that the tree owns every scalar it refers to.
c4::csubstr ArenaSubstrFromString(ryml::Tree &tree, NSString * _Nullable string) {
    if (string == nil) {
        return c4::csubstr{};
    }

    const char *utf8 = [string UTF8String];
    size_t length = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return tree.copy_to_arena(c4::csubstr(utf8, length));
}

ryml::type_bits KeyStyleBits(YAMLScalarStyle style) {
    switch (style) {
        case YAMLScalarStyleLiteral: return ryml::KEY_LITERAL;
        case YAMLScalarStyleFolded: return ryml::KEY_FOLDED;
        case YAMLScalarStyleSingleQuoted: return ryml::KEY_SQUO;
        case YAMLScalarStyleDoubleQuoted: return ryml::KEY_DQUO;
        case YAMLScalarStylePlain: return ryml::KEY_PLAIN;
        case YAMLScalarStyleAny: return 0;
    }
    return 0;
}

ryml::type_bits ValueStyleBits(YAMLScalarStyle style) {
    switch (style) {
        case YAMLScalarStyleLiteral: return ryml::VAL_LITERAL;
        case YAMLScalarStyleFolded: return ryml::VAL_FOLDED;
        case YAMLScalarStyleSingleQuoted: return ryml::VAL_SQUO;
        case YAMLScalarStyleDoubleQuoted: return ryml::VAL_DQUO;
        case YAMLScalarStylePlain: return ryml::VAL_PLAIN;
        case YAMLScalarStyleAny: return 0;
    }
    return 0;
}

ryml::type_bits CollectionStyleBits(YAMLCollectionStyle style) {
    switch (style) {
        case YAMLCollectionStyleFlow: return ryml::FLOW_SL;
        case YAMLCollectionStyleBlock: return ryml::BLOCK;
        case YAMLCollectionStyleAny: return 0;
    }
    return 0;
}

/// Writes `description` and everything below it into the node `id`, which is already parented.
void BuildNode(ryml::Tree &tree, ryml::id_type id, YAMLEmitterNode *description) {
    if (description.key != nil) {
        tree.set_key(id, ArenaSubstrFromString(tree, description.key));
        ryml::type_bits style = KeyStyleBits(description.keyStyle);
        if (style != 0) {
            tree.set_key_style(id, style);
        }
        if (description.keyTag != nil) {
            tree.set_key_tag(id, ArenaSubstrFromString(tree, description.keyTag));
        }
        if (description.keyAnchor != nil) {
            tree.set_key_anchor(id, ArenaSubstrFromString(tree, description.keyAnchor));
        }
    }

    if (description.valueAlias != nil) {
        tree.set_val_ref(id, ArenaSubstrFromString(tree, description.valueAlias));
        return;
    }

    switch (description.kind) {
        case YAMLNodeKindMapping:
            tree.set_map(id);
            break;
        case YAMLNodeKindSequence:
            tree.set_seq(id);
            break;
        default:
            tree.set_val(id, ArenaSubstrFromString(tree, description.value ?: @""));
            break;
    }

    if (description.kind == YAMLNodeKindMapping || description.kind == YAMLNodeKindSequence) {
        ryml::type_bits style = CollectionStyleBits(description.collectionStyle);
        if (style != 0) {
            tree._add_flags(id, style);
        }
    } else {
        ryml::type_bits style = ValueStyleBits(description.valueStyle);
        if (style == 0) {
            // Left to itself, rapidyaml picks a block style, and `scalar_style_choose_block()`
            // asserts rather than falling back when a scalar can be neither plain nor
            // single-quoted — a multi-line string with indented continuation lines, say. The
            // assert routes through the error callbacks, and since that function is `noexcept`
            // the throw would terminate the process. Choosing here avoids the whole path, and
            // picks what libyaml picks: plain, else single-quoted, else double-quoted.
            style = static_cast<ryml::type_bits>(ryml::scalar_style_choose_flow(tree.val(id))) & ryml::VAL_STYLE;
        }
        if (style != 0) {
            tree.set_val_style(id, style);
        }
    }

    if (description.valueTag != nil) {
        tree.set_val_tag(id, ArenaSubstrFromString(tree, description.valueTag));
    }
    if (description.valueAnchor != nil) {
        tree.set_val_anchor(id, ArenaSubstrFromString(tree, description.valueAnchor));
    }

    for (YAMLEmitterNode *child in description.children) {
        BuildNode(tree, tree.append_child(id), child);
    }
}

}

@implementation YAMLEmitterNode
@end

@implementation YAMLEmitter

+ (nullable NSString *)emitDocuments:(NSArray<YAMLEmitterNode *> *)documents
                       explicitStart:(BOOL)explicitStart
                               error:(NSError **)error {
    CRapidYAMLInstallErrorCallbacks();

    try {
        ryml::Tree tree;
        ryml::id_type root = tree.root_id();

        // rapidyaml writes `---` for every document of a STREAM, and for nothing else, so the
        // stream wrapper is what an explicit start amounts to.
        if (documents.count == 1 && !explicitStart) {
            BuildNode(tree, root, documents.firstObject);
        } else {
            tree.set_stream(root);
            for (YAMLEmitterNode *document in documents) {
                ryml::id_type child = tree.append_child(root);
                tree.set_doc(child);
                BuildNode(tree, child, document);
            }
        }

        std::string emitted = ryml::emitrs_yaml<std::string>(tree);
        return [[NSString alloc] initWithBytes:emitted.data()
                                        length:emitted.size()
                                      encoding:NSUTF8StringEncoding];
    } catch (CRapidYAMLException const& exception) {
        if (error != NULL) {
            *error = CRapidYAMLErrorFromException(exception);
        }
        return nil;
    }
}

@end
