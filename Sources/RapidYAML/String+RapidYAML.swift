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

    /// Converts a position reported by rapidyaml into a `Mark`.
    ///
    /// rapidyaml counts columns in bytes, while `Mark` — like libYAML, which Yams is built on —
    /// counts them in `UnicodeScalar`. The two only differ once a line contains multibyte
    /// characters before the reported position.
    ///
    /// - parameter line:   Line number starting from 1.
    /// - parameter column: Column number starting from 1, counted in UTF-8 bytes.
    func mark(atLine line: Int, byteColumn column: Int) -> Mark {
        let contents = substring(at: line - 1)
        guard let index = contents.utf8
            .index(contents.utf8.startIndex, offsetBy: column - 1, limitedBy: contents.utf8.endIndex)?
            .samePosition(in: contents.unicodeScalars) else {
            return Mark(line: line, column: column)
        }
        let scalarColumn = contents.unicodeScalars.distance(from: contents.unicodeScalars.startIndex, to: index)
        return Mark(line: line, column: scalarColumn + 1)
    }
}
