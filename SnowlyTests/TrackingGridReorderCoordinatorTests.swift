//
//  TrackingGridReorderCoordinatorTests.swift
//  SnowlyTests
//

import Testing
import Foundation
import CoreGraphics
@testable import Snowly

struct TrackingGridReorderCoordinatorTests {

    private let metrics = TrackingGridLayoutMetrics(
        gridWidth: 210,
        cardHeight: 88,
        gutter: 10
    )

    private struct Item: Identifiable, Equatable {
        let id: UUID
        let label: String
    }

    @Test func cardCenter_usesGridMetrics() {
        #expect(metrics.cardCenter(at: 0) == CGPoint(x: 50, y: 44))
        #expect(metrics.cardCenter(at: 1) == CGPoint(x: 160, y: 44))
        #expect(metrics.cardCenter(at: 2) == CGPoint(x: 50, y: 142))
    }

    @Test func targetIndex_returnsNilInsideDeadZones() {
        let columnGap = CGPoint(x: 105, y: 44)
        let rowGap = CGPoint(x: 50, y: 92)

        #expect(metrics.targetIndex(for: columnGap, itemCount: 4, excluding: 0) == nil)
        #expect(metrics.targetIndex(for: rowGap, itemCount: 4, excluding: 0) == nil)
    }

    @Test func targetIndex_clampsIntoLastItemForIncompleteRow() {
        let lowerRight = CGPoint(x: 160, y: 260)

        let index = metrics.targetIndex(for: lowerRight, itemCount: 5, excluding: 0)

        #expect(index == 4)
    }

    @Test func targetIndex_returnsNilForCurrentSlot() {
        let index = metrics.targetIndex(for: metrics.cardCenter(at: 1), itemCount: 4, excluding: 1)

        #expect(index == nil)
    }

    @Test func makeDragSession_tracksStartIndexAndCenter() {
        let ids = [UUID(), UUID(), UUID()]
        let items = [
            Item(id: ids[0], label: "A"),
            Item(id: ids[1], label: "B"),
            Item(id: ids[2], label: "C"),
        ]

        let session = TrackingGridReorderCoordinator.makeDragSession(
            for: ids[1],
            in: items,
            metrics: metrics
        )

        #expect(session?.draggingId == ids[1])
        #expect(session?.startIndex == 1)
        #expect(session?.currentIndex == 1)
        #expect(session?.dragStartCenter == metrics.cardCenter(at: 1))
    }

    @Test func reorder_movesElementIntoTargetSlot() {
        let items = ["A", "B", "C", "D"]

        let reordered = TrackingGridReorderCoordinator.reorder(items, from: 0, to: 2)

        #expect(reordered == ["B", "C", "A", "D"])
    }
}
