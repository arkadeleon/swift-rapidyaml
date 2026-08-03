//
//  CRapidYAML.h
//  CRapidYAML
//
//  Created by Leon Li on 2025/6/12.
//
//  The C++ side of the library: rapidyaml itself, vendored under `c4core/` and `ryml/`, and a
//  thin bridge over it. Nothing here is public API — `RapidYAML` imports it internally and
//  presents `Node`, `Parser` and the rest on top.
//

#import "CRapidYAMLError.h"
#import "CRapidYAMLTree.h"
#import "CRapidYAMLEmitter.h"
