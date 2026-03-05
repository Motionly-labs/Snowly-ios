//
//  CircularBuffer.swift
//  Snowly
//
//  O(1) append with fixed-capacity circular buffer.
//  Replaces Array patterns where removeFirst() is O(n).
//

import Foundation

struct CircularBuffer<Element>: Sendable where Element: Sendable {
    private var storage: [Element?]
    private var head: Int = 0
    private var tail: Int = 0
    private(set) var count: Int = 0

    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "CircularBuffer capacity must be positive")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    var isEmpty: Bool { count == 0 }

    mutating func append(_ element: Element) {
        storage[tail] = element
        tail = (tail + 1) % capacity

        if count == capacity {
            // Overwrite oldest element
            head = (head + 1) % capacity
        } else {
            count += 1
        }
    }

    /// Returns elements in insertion order (oldest first).
    var elements: [Element] {
        guard count > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let index = (head + i) % capacity
            if let element = storage[index] {
                result.append(element)
            }
        }
        return result
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        tail = 0
        count = 0
    }
}
