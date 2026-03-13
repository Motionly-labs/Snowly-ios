//
//  CircularBufferTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

struct CircularBufferTests {

    @Test func append_underCapacity() {
        var buffer = CircularBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)

        #expect(buffer.count == 3)
        #expect(buffer.elements == [1, 2, 3])
    }

    @Test func append_atCapacity_wraps() {
        var buffer = CircularBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.append(4)

        #expect(buffer.count == 3)
        #expect(buffer.elements == [2, 3, 4])
    }

    @Test func append_multipleWraps() {
        var buffer = CircularBuffer<Int>(capacity: 2)
        for i in 1...10 {
            buffer.append(i)
        }

        #expect(buffer.count == 2)
        #expect(buffer.elements == [9, 10])
    }

    @Test func elements_preservesInsertionOrder() {
        var buffer = CircularBuffer<String>(capacity: 4)
        buffer.append("a")
        buffer.append("b")
        buffer.append("c")
        buffer.append("d")
        buffer.append("e")  // wraps, pushes out "a"

        #expect(buffer.elements == ["b", "c", "d", "e"])
    }

    @Test func removeAll_clearsBuffer() {
        var buffer = CircularBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.removeAll()

        #expect(buffer.count == 0)
        #expect(buffer.isEmpty)
        #expect(buffer.elements == [])
    }

    @Test func isEmpty_initialState() {
        let buffer = CircularBuffer<Int>(capacity: 3)
        #expect(buffer.isEmpty)
        #expect(buffer.count == 0)
    }

    @Test func capacity_preserved() {
        let buffer = CircularBuffer<Int>(capacity: 10)
        #expect(buffer.capacity == 10)
    }

    @Test func singleElement_buffer() {
        var buffer = CircularBuffer<Int>(capacity: 1)
        buffer.append(42)
        #expect(buffer.elements == [42])

        buffer.append(99)
        #expect(buffer.count == 1)
        #expect(buffer.elements == [99])
    }
}
