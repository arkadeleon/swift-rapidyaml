//
//  YAMLError.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation
internal import YAMLNode

/// Errors thrown by RapidYAML APIs.
public enum YAMLError: Error, Sendable {
    /// No error is produced.
    case no

    /// Cannot allocate or reallocate a block of memory.
    case memory

    /// Cannot read or decode the input stream.
    ///
    /// - parameter problem: Error description.
    /// - parameter offset:  The offset from `yaml.startIndex` at which the problem occured.
    /// - parameter value:   The problematic value (-1 is none).
    /// - parameter yaml:    YAML String which the problem occured while reading.
    case reader(problem: String, offset: Int?, value: Int32, yaml: String)

    // line and column start from 1, column is counted by unicodeScalars
    /// Cannot scan the input stream.
    ///
    /// - parameter context: Error context.
    /// - parameter problem: Error description.
    /// - parameter mark:    Problem position.
    /// - parameter yaml:    YAML String which the problem occured while scanning.
    case scanner(context: Context?, problem: String, Mark, yaml: String)

    /// Cannot parse the input stream.
    ///
    /// - parameter context: Error context.
    /// - parameter problem: Error description.
    /// - parameter mark:    Problem position.
    /// - parameter yaml:    YAML String which the problem occured while parsing.
    case parser(context: Context?, problem: String, Mark, yaml: String)

    /// Cannot compose a YAML document.
    ///
    /// - parameter context: Error context.
    /// - parameter problem: Error description.
    /// - parameter mark:    Problem position.
    /// - parameter yaml:    YAML String which the problem occured while composing.
    case composer(context: Context?, problem: String, Mark, yaml: String)

    /// Cannot write to the output stream.
    ///
    /// - parameter problem: Error description.
    case writer(problem: String)

    /// Cannot emit a YAML stream.
    ///
    /// - parameter problem: Error description.
    case emitter(problem: String)

    /// Used in `NodeRepresentable`.
    ///
    /// - parameter problem: Error description.
    case representer(problem: String)

    /// String data could not be decoded with the specified encoding.
    ///
    /// - parameter encoding: The string encoding used to decode the string data.
    case dataCouldNotBeDecoded(encoding: String.Encoding)

    /// Multiple uses of the same key detected in a mapping
    ///
    /// - parameter duplicates: A dictionary keyed by the duplicated node value, with all nodes that duplicate the value
    /// - parameter context:    Position of the duplication.
    case duplicatedKeysInMapping(duplicates: [String], context: Context)

    /// The error context.
    public struct Context: CustomStringConvertible, Sendable {
        /// Context text.
        public let text: String
        /// Context position.
        public let mark: Mark
        /// A textual representation of this instance.
        public var description: String {
            return text + " in line \(mark.line), column \(mark.column)\n"
        }
    }
}

extension YAMLError {

    /// Creates a `YAMLError` from an error reported by the underlying rapidyaml library.
    ///
    /// rapidyaml classifies errors more coarsely than libYAML, which Yams' `YamlError` cases were
    /// modelled on: it distinguishes a *parse* error, which carries a position in the YAML source,
    /// from *basic* and *visit* errors, which do not. There is nothing corresponding to libYAML's
    /// separate scanner and composer stages, so `.scanner` and `.composer` are never produced.
    ///
    /// rapidyaml also has no equivalent of libYAML's error context — the "while parsing a block
    /// mapping" half of the message — so `context` is always `nil`.
    ///
    /// - parameter error: An `NSError` in `YAMLNodeErrorDomain`.
    /// - parameter yaml:  The YAML String being parsed when the error occured.
    init(from error: NSError, with yaml: String) {
        guard error.domain == YAMLNodeErrorDomain else {
            self = .reader(problem: error.localizedDescription, offset: nil, value: -1, yaml: yaml)
            return
        }

        let problem = error.localizedDescription

        switch YAMLNodeError.Code(rawValue: error.code) {
        case .parse:
            guard let line = error.userInfo[YAMLNodeErrorLineKey] as? Int,
                  let column = error.userInfo[YAMLNodeErrorColumnKey] as? Int else {
                let offset = error.userInfo[YAMLNodeErrorOffsetKey] as? Int
                self = .reader(problem: problem, offset: offset, value: -1, yaml: yaml)
                return
            }
            self = .parser(context: nil, problem: problem, LineIndex(yaml).mark(atLine: line, byteColumn: column), yaml: yaml)
        default:
            // Basic and visit errors carry a location in the rapidyaml C++ source rather than in
            // the YAML, so there is no mark to report.
            self = .reader(problem: problem, offset: nil, value: -1, yaml: yaml)
        }
    }
}

extension YAMLError: CustomStringConvertible {
    /// A textual representation of this instance.
    public var description: String {
        switch self {
        case .no:
            return "No error is produced"
        case .memory:
            return "Memory error"
        case let .reader(problem, offset, value, yaml):
            guard let (line, column, contents) = offset.flatMap(yaml.lineNumberColumnAndContents(at:)) else {
                return "\(problem) at offset: \(String(describing: offset)), value: \(value)"
            }
            let mark = Mark(line: line + 1, column: column + 1)
            return "\(mark): error: reader: \(problem):\n" + contents.endingWithNewLine
                + String(repeating: " ", count: column) + "^"
        case let .scanner(context, problem, mark, yaml):
            return "\(mark): error: scanner: \(context?.description ?? "")\(problem):\n" + mark.snippet(from: yaml)
        case let .parser(context, problem, mark, yaml):
            return "\(mark): error: parser: \(context?.description ?? "")\(problem):\n" + mark.snippet(from: yaml)
        case let .composer(context, problem, mark, yaml):
            return "\(mark): error: composer: \(context?.description ?? "")\(problem):\n" + mark.snippet(from: yaml)
        case let .writer(problem), let .emitter(problem), let .representer(problem):
            return problem
        case .dataCouldNotBeDecoded(encoding: let encoding):
            return "String could not be decoded from data using '\(encoding)' encoding"
        case let .duplicatedKeysInMapping(duplicates, context):
            let duplicateKeys = duplicates.sorted().map { "'\($0)'" }.joined(separator: ", ")
            return """
                   Parser: expected all keys to be unique but found the following duplicated key(s): \(duplicateKeys).
                   Context:
                   \(context.description)
                   """
        }
    }
}
