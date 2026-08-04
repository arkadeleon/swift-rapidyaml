//
//  CRapidYAMLError.h
//  CRapidYAML
//
//  Created by Leon Li on 2025/6/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Domain of the errors reported by the underlying rapidyaml library.
///
/// Nothing outside this package sees one: `RapidYAML.YAMLError` is built from it and thrown
/// instead.
extern NSErrorDomain const CRapidYAMLErrorDomain;

typedef NS_ERROR_ENUM(CRapidYAMLErrorDomain, CRapidYAMLErrorCode) {
    /// A general error, not tied to a location in the YAML source.
    CRapidYAMLErrorCodeBasic = 1,
    /// The YAML source is malformed. The location keys below point at the offending token.
    CRapidYAMLErrorCodeParse = 2,
    /// An error raised while visiting an already parsed tree.
    CRapidYAMLErrorCodeVisit = 3,
};

/// One-based line in the YAML source where the error was detected, as an `NSNumber`.
///
/// Only present on `CRapidYAMLErrorCodeParse` errors.
extern NSErrorUserInfoKey const CRapidYAMLErrorLineKey;

/// One-based column in the YAML source where the error was detected, as an `NSNumber`.
///
/// Only present on `CRapidYAMLErrorCodeParse` errors.
extern NSErrorUserInfoKey const CRapidYAMLErrorColumnKey;

/// Zero-based byte offset into the YAML source where the error was detected, as an `NSNumber`.
///
/// Unlike the line and column above, which rapidyaml reports one-based, this one counts from 0 —
/// and `YAMLError.reader` expects it that way, being an offset from `yaml.startIndex`.
///
/// Only present on `CRapidYAMLErrorCodeParse` errors.
extern NSErrorUserInfoKey const CRapidYAMLErrorOffsetKey;

NS_ASSUME_NONNULL_END
