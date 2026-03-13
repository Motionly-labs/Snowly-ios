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

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

extension Array {
    /// Returns the array with duplicates removed, preserving first occurrence.
    /// The key used for comparison is extracted via `keyPath`.
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen: Set<T> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
