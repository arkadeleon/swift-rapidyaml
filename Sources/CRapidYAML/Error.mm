//
//  Error.mm
//  CRapidYAML
//
//  Created by Leon Li on 2025/6/12.
//

#import "include/CRapidYAMLError.h"
#import "Internal.h"

NSErrorDomain const CRapidYAMLErrorDomain = @"RapidYAMLErrorDomain";

NSErrorUserInfoKey const CRapidYAMLErrorLineKey = @"RapidYAMLErrorLine";
NSErrorUserInfoKey const CRapidYAMLErrorColumnKey = @"RapidYAMLErrorColumn";
NSErrorUserInfoKey const CRapidYAMLErrorOffsetKey = @"RapidYAMLErrorOffset";

namespace {

[[noreturn]] void ThrowBasicError(c4::csubstr msg, ryml::ErrorDataBasic const&, void *) {
    throw CRapidYAMLException{CRapidYAMLErrorCodeBasic, std::string(msg.str, msg.len), false, 0, 0, 0};
}

[[noreturn]] void ThrowParseError(c4::csubstr msg, ryml::ErrorDataParse const& errdata, void *) {
    ryml::Location const& loc = errdata.ymlloc;
    throw CRapidYAMLException{
        CRapidYAMLErrorCodeParse,
        std::string(msg.str, msg.len),
        static_cast<bool>(loc),
        loc.offset,
        loc.line,
        loc.col,
    };
}

[[noreturn]] void ThrowVisitError(c4::csubstr msg, ryml::ErrorDataVisit const&, void *) {
    throw CRapidYAMLException{CRapidYAMLErrorCodeVisit, std::string(msg.str, msg.len), false, 0, 0, 0};
}

/// Installs the throwing error callbacks. rapidyaml keeps them in global state, and objects
/// copy them from there at construction time, so this must run before the first parse.
void CRapidYAMLInstallErrorCallbacks() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ryml::Callbacks callbacks;
        callbacks.set_error_basic(ThrowBasicError);
        callbacks.set_error_parse(ThrowParseError);
        callbacks.set_error_visit(ThrowVisitError);
        ryml::set_callbacks(callbacks);
    });
}

}

void CRapidYAMLInstallErrorCallbacks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ryml::Callbacks callbacks;
        callbacks.set_error_basic(ThrowBasicError);
        callbacks.set_error_parse(ThrowParseError);
        callbacks.set_error_visit(ThrowVisitError);
        ryml::set_callbacks(callbacks);
    });
}

NSError *CRapidYAMLErrorFromException(CRapidYAMLException const& exception) {
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];

    NSString *message = [[NSString alloc] initWithBytes:exception.message.data()
                                                 length:exception.message.size()
                                               encoding:NSUTF8StringEncoding];
    if (message != nil) {
        userInfo[NSLocalizedDescriptionKey] = message;
    }

    if (exception.hasLocation) {
        if (exception.offset != ryml::npos) {
            userInfo[CRapidYAMLErrorOffsetKey] = @(exception.offset);
        }
        if (exception.line != ryml::npos) {
            userInfo[CRapidYAMLErrorLineKey] = @(exception.line);
        }
        if (exception.col != ryml::npos) {
            userInfo[CRapidYAMLErrorColumnKey] = @(exception.col);
        }
    }

    return [NSError errorWithDomain:CRapidYAMLErrorDomain code:exception.code userInfo:userInfo];
}
