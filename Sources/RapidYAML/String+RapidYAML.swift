//
//  String+RapidYAML.swift
//  RapidYAML
//
//  Created by Leon Li on 2026/8/3.
//

import Foundation

extension String {
    typealias LineNumberColumnAndContents = (lineNumber: Int, column: Int, contents: String)

    /// line number, column and contents at offset.
    ///
    /// - parameter offset: Int
    ///
    /// - returns: lineNumber: line number start from 0,
    ///            column: utf16 column start from 0,
    ///            contents: substring of line
    func lineNumberColumnAndContents(at offset: Int) -> LineNumberColumnAndContents? {
        return index(startIndex, offsetBy: offset, limitedBy: endIndex).flatMap(lineNumberColumnAndContents)
    }

    /// line number, column and contents at Index.
    ///
    /// - parameter index: String.Index
    ///
    /// - returns: lineNumber: line number start from 0,
    ///            column: utf16 column start from 0,
    ///            contents: substring of line
    func lineNumberColumnAndContents(at index: Index) -> LineNumberColumnAndContents {
        assert((startIndex..<endIndex).contains(index))
        var number = 0
        var outStartIndex = startIndex, outEndIndex = startIndex, outContentsEndIndex = startIndex
        getLineStart(&outStartIndex, end: &outEndIndex, contentsEnd: &outContentsEndIndex,
                     for: startIndex..<startIndex)
        while outEndIndex <= index && outEndIndex < endIndex {
            number += 1
            let range: Range = outEndIndex..<outEndIndex
            getLineStart(&outStartIndex, end: &outEndIndex, contentsEnd: &outContentsEndIndex,
                         for: range)
        }
        let utf16StartIndex = outStartIndex.samePosition(in: utf16)!
        let utf16Index = index.samePosition(in: utf16)!
        return (
            number,
            utf16.distance(from: utf16StartIndex, to: utf16Index),
            String(self[outStartIndex..<outEndIndex])
        )
    }

    /// substring indicated by line number.
    ///
    /// - parameter line: line number starts from 0.
    ///
    /// - returns: substring of line contains line ending characters
    func substring(at line: Int) -> String {
        var number = 0
        var outStartIndex = startIndex, outEndIndex = startIndex, outContentsEndIndex = startIndex
        getLineStart(&outStartIndex, end: &outEndIndex, contentsEnd: &outContentsEndIndex,
                     for: startIndex..<startIndex)
        while number < line && outEndIndex < endIndex {
            number += 1
            let range: Range = outEndIndex..<outEndIndex
            getLineStart(&outStartIndex, end: &outEndIndex, contentsEnd: &outContentsEndIndex,
                         for: range)
        }
        return String(self[outStartIndex..<outEndIndex])
    }

    /// String appending newline if is not ending with newline.
    var endingWithNewLine: String {
        let isEndsWithNewLines = unicodeScalars.last.map(CharacterSet.newlines.contains) ?? false
        if isEndsWithNewLines {
            return self
        } else {
            return self + "\n"
        }
    }

}

/// Where each line of a source begins, recorded once, so that resolving a mark costs at most the
/// length of one line rather than a walk from the top of the document.
///
/// Composing a document asks for a mark per scalar. Going through `substring(at:)` each time made
/// that quadratic in the size of the source: composing a 74 KB file took 440 ms, against under a
/// millisecond to parse it.
struct LineIndex {

    private let yaml: String
    /// Where each line begins, so a lookup neither walks nor copies the source.
    private let lineStarts: [String.Index]
    /// Whether each line is pure ASCII, where a byte column is already a scalar column.
    private let lineIsASCII: [Bool]

    init(_ yaml: String) {
        self.yaml = yaml

        // rapidyaml counts lines by `\n`, so this counts them the same way. Scanning scalars
        // rather than characters keeps this off the grapheme-breaking path.
        let scalars = yaml.unicodeScalars
        var starts: [String.Index] = [scalars.startIndex]
        var isASCII: [Bool] = []
        var currentIsASCII = true
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let next = scalars.index(after: index)
            if scalars[index] == "\n" {
                starts.append(next)
                isASCII.append(currentIsASCII)
                currentIsASCII = true
            } else if !scalars[index].isASCII {
                currentIsASCII = false
            }
            index = next
        }
        isASCII.append(currentIsASCII)

        lineStarts = starts
        lineIsASCII = isASCII
    }

    /// Converts a position reported by rapidyaml into a `Mark`.
    ///
    /// rapidyaml counts columns in bytes, while `Mark` — like libYAML, which Yams is built on —
    /// counts them in `UnicodeScalar`. The two only differ once a line contains multibyte
    /// characters before the reported position.
    ///
    /// - parameter line:   Line number starting from 1.
    /// - parameter column: Column number starting from 1, counted in UTF-8 bytes.
    func mark(atLine line: Int, byteColumn column: Int) -> Mark {
        guard line >= 1, line <= lineStarts.count else {
            return Mark(line: line, column: column)
        }

        // Walking to a column is linear in the column, and a flow sequence written on one line
        // can run to thousands. Almost all YAML is ASCII, where there is nothing to convert.
        if lineIsASCII[line - 1] {
            return Mark(line: line, column: column)
        }

        let lineStart = lineStarts[line - 1]
        guard let index = yaml.utf8.index(lineStart, offsetBy: column - 1, limitedBy: yaml.utf8.endIndex),
              let scalarIndex = index.samePosition(in: yaml.unicodeScalars) else {
            return Mark(line: line, column: column)
        }
        let scalarColumn = yaml.unicodeScalars.distance(from: lineStart, to: scalarIndex)
        return Mark(line: line, column: scalarColumn + 1)
    }
}
