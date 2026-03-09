//
//  String+Extensions.swift
//  Snowly
//

import Foundation

extension String {
    /// Returns the string if non-empty, or nil.
    var nonEmpty: String? { isEmpty ? nil : self }
}
