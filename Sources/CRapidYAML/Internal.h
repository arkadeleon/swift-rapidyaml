//
//  Internal.h
//  CRapidYAML
//
//  Created by Leon Li on 2025/6/12.
//
//  Shared between this target's implementation files. Not part of the module: it pulls in the
//  rapidyaml headers, which are C++ and must not reach Swift.
//

#import <Foundation/Foundation.h>

#import "ryml/ryml.hpp"
// `emitrs_yaml<std::string>` needs c4core's std::string adapters.
#import "c4core/c4/std/string.hpp"

#import "include/CRapidYAMLError.h"

#include <string>

/// The exception the error callbacks throw. Declared here so that every entry point can catch it.
struct CRapidYAMLException {
    CRapidYAMLErrorCode code;
    std::string message;
    /// Location in the YAML source. Only meaningful for parse errors; the other error kinds
    /// only carry a location in the rapidyaml C++ source, which is of no use to a caller.
    bool hasLocation;
    size_t offset;
    size_t line;
    size_t col;
};

/// Installs the throwing error callbacks. Every entry point calls this before touching rapidyaml.
void CRapidYAMLInstallErrorCallbacks(void);

/// Turns a caught exception into the error an entry point reports.
NSError *CRapidYAMLErrorFromException(CRapidYAMLException const& exception);
