//
//  Tree.mm
//  CRapidYAML
//
//  Created by Leon Li on 2025/6/12.
//

#import "include/CRapidYAMLTree.h"
#import "Internal.h"

#include <memory>

namespace {

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
static void YAMLLocationOfScalar(c4::csubstr scalar, ryml::Parser const& parser, size_t *line, size_t *column) {
    *line = 0;
    *column = 0;

    if (scalar.str == nullptr || !scalar.is_sub(parser.source())) {
        return;
    }

    try {
        ryml::Location location = parser.val_location(scalar.str);
        if (location.line != ryml::npos) {
            *line = location.line + 1;
        }
        if (location.col != ryml::npos) {
            *column = location.col + 1;
        }
    } catch (CRapidYAMLException const&) {
        // rapidyaml's line accelerator cannot resolve every position — a scalar on the last line
        // of a source with no trailing newline sits past the last recorded newline, and the
        // lookup fails. A node without a mark beats a parse that does not happen.
        *line = 0;
        *column = 0;
    }
}

}

extern "C" const YAMLNodeID YAMLTreeNoNode = (YAMLNodeID)-1;

/// A parsed tree, with the parser it came from.
///
/// The parser has to outlive the tree: it owns the line accelerator that resolves a scalar's
/// position, and `YAMLTreeRead` asks for one on every node.
struct YAMLTree {
    ryml::EventHandlerTree eventHandler;
    ryml::Parser parser;
    ryml::Tree tree;

    YAMLTree() : eventHandler(), parser(&eventHandler, ryml::ParserOptions().locations(true)), tree() {}
};

static YAMLStringRef YAMLStringRefFromSubstr(c4::csubstr substr) {
    return YAMLStringRef{substr.str, substr.len};
}

/// Converts a tag as written into its long form, so that `!!str` and `!<tag:yaml.org,2002:str>`
/// both arrive in Swift as `tag:yaml.org,2002:str` — the form libyaml hands to Yams. Tags that are
/// not from the YAML schema, such as `!foo`, are passed through unchanged.
static YAMLStringRef YAMLStringRefFromTag(c4::csubstr tag) {
    if (tag.str == nullptr) {
        return YAMLStringRef{nullptr, 0};
    }

    c4::csubstr normalized = ryml::normalize_tag_long(tag);
    if (normalized.len >= 2 && normalized.begins_with('<') && normalized.ends_with('>')) {
        normalized = normalized.range(1, normalized.len - 1);
    }
    return YAMLStringRefFromSubstr(normalized);
}

extern "C" YAMLTree * _Nullable YAMLTreeParse(const char *yaml, size_t length, NSError **error) {
    CRapidYAMLInstallErrorCallbacks();

    try {
        // Constructing the tree allocates, and a failed allocation reports through the same
        // callbacks — so it belongs inside the `try`. Anything thrown out of here would cross
        // back into Swift, where there is no handler and the process ends.
        auto handle = std::make_unique<YAMLTree>();

        // Locations are opt-in because tracking them costs an extra pass over the source. `Mark`
        // is part of the public model, so they are always on.
        ryml::parse_in_arena(&handle->parser, c4::csubstr(yaml, length), &handle->tree);
        return handle.release();
    } catch (CRapidYAMLException const& exception) {
        if (error != NULL) {
            *error = CRapidYAMLErrorFromException(exception);
        }
        return nullptr;
    } catch (...) {
        // Not ours — `std::bad_alloc` from the allocation above, say. It still must not escape.
        if (error != NULL) {
            *error = CRapidYAMLUnknownError();
        }
        return nullptr;
    }
}

extern "C" void YAMLTreeFree(YAMLTree * _Nullable tree) {
    delete tree;
}

extern "C" YAMLNodeID YAMLTreeRoot(const YAMLTree *tree) {
    return tree->tree.root_id();
}

extern "C" YAMLNodeID YAMLTreeFirstChild(const YAMLTree *tree, YAMLNodeID node) {
    ryml::id_type child = tree->tree.first_child(node);
    return child == ryml::NONE ? YAMLTreeNoNode : child;
}

extern "C" YAMLNodeID YAMLTreeNextSibling(const YAMLTree *tree, YAMLNodeID node) {
    ryml::id_type sibling = tree->tree.next_sibling(node);
    return sibling == ryml::NONE ? YAMLTreeNoNode : sibling;
}

extern "C" void YAMLTreeRead(const YAMLTree *handle, YAMLNodeID node, YAMLNodeRecord *record) {
    ryml::ConstNodeRef ref = handle->tree.cref(node);

    *record = YAMLNodeRecord{};
    record->kind = YAMLNodeKindFromNode(ref);
    record->childCount = ref.num_children();
    record->collectionStyle = YAMLCollectionStyleFromNode(ref);

    record->hasKey = ref.has_key();
    if (ref.has_key()) {
        record->key = YAMLStringRefFromSubstr(ref.key());
        record->keyStyle = YAMLKeyStyleFromNode(ref);
        YAMLLocationOfScalar(ref.key(), handle->parser, &record->keyLine, &record->keyColumn);
    }
    if (ref.has_key_tag()) {
        record->keyTag = YAMLStringRefFromTag(ref.key_tag());
    }
    if (ref.has_key_anchor()) {
        record->keyAnchor = YAMLStringRefFromSubstr(ref.key_anchor());
    }
    if (ref.is_key_ref()) {
        record->keyAlias = YAMLStringRefFromSubstr(ref.key_ref());
    }

    if (ref.has_val()) {
        record->value = YAMLStringRefFromSubstr(ref.val());
        record->valueStyle = YAMLValueStyleFromNode(ref);
        YAMLLocationOfScalar(ref.val(), handle->parser, &record->valueLine, &record->valueColumn);
    }
    if (ref.has_val_tag()) {
        record->valueTag = YAMLStringRefFromTag(ref.val_tag());
    }
    if (ref.has_val_anchor()) {
        record->valueAnchor = YAMLStringRefFromSubstr(ref.val_anchor());
    }
    if (ref.is_val_ref()) {
        record->valueAlias = YAMLStringRefFromSubstr(ref.val_ref());
    }

    // A container has no scalar to point at, so stand in the position of its first child.
    if (record->valueLine == 0 && record->childCount > 0) {
        ryml::ConstNodeRef first = ref.child(0);
        c4::csubstr scalar = first.has_key() ? first.key() : (first.has_val() ? first.val() : c4::csubstr{});
        YAMLLocationOfScalar(scalar, handle->parser, &record->valueLine, &record->valueColumn);
    }
}
