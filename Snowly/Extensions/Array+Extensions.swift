//
//  Array+Extensions.swift
//  Snowly
//

import Foundation

extension Array {
    /// Returns the middle element, or nil if the array is empty.
    var midElement: Element? {
        guard !isEmpty else { return nil }
        return self[count / 2]
    }
}
