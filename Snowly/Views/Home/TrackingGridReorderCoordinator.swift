//
//  TrackingGridReorderCoordinator.swift
//  Snowly
//
//  Pure layout math and reorder helpers for the active tracking stat grid.
//  Keeps drag hit-testing and index shuffling testable outside the view body.
//

import Foundation
import CoreGraphics

struct TrackingGridLayoutMetrics: Equatable {
    let gridWidth: CGFloat
    let cardHeight: CGFloat
    let gutter: CGFloat
    let columnCount: Int

    init(
        gridWidth: CGFloat,
        cardHeight: CGFloat,
        gutter: CGFloat,
        columnCount: Int = 2
    ) {
        self.gridWidth = max(gridWidth, 0)
        self.cardHeight = cardHeight
        self.gutter = gutter
        self.columnCount = max(columnCount, 1)
    }

    var columnWidth: CGFloat {
        let totalGutterWidth = CGFloat(max(columnCount - 1, 0)) * gutter
        return max((gridWidth - totalGutterWidth) / CGFloat(columnCount), 0)
    }

    var rowHeight: CGFloat {
        cardHeight + gutter
    }

    func cardCenter(at index: Int) -> CGPoint {
        let safeIndex = max(index, 0)
        let column = safeIndex % columnCount
        let row = safeIndex / columnCount

        return CGPoint(
            x: CGFloat(column) * (columnWidth + gutter) + columnWidth / 2,
            y: CGFloat(row) * rowHeight + cardHeight / 2
        )
    }

    func targetIndex(
        for position: CGPoint,
        itemCount: Int,
        excluding sourceIndex: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }

        let normalizedY = max(position.y, 0)
        let rowFraction = rowHeight > 0
            ? normalizedY.truncatingRemainder(dividingBy: rowHeight)
            : 0
        guard rowFraction <= cardHeight else { return nil }

        let stride = columnWidth + gutter
        let normalizedX = max(position.x, 0)
        let rawColumn = stride > 0 ? Int(normalizedX / stride) : 0
        let column = max(0, min(rawColumn, columnCount - 1))
        let columnOrigin = CGFloat(column) * stride
        let inColumnGap = column < columnCount - 1 &&
            normalizedX > columnOrigin + columnWidth &&
            normalizedX < columnOrigin + stride
        guard !inColumnGap else { return nil }

        let maxRow = (itemCount - 1) / columnCount
        let row = min(Int(normalizedY / max(rowHeight, 1)), maxRow)
        let candidate = min(row * columnCount + column, itemCount - 1)
        return candidate == sourceIndex ? nil : candidate
    }
}

struct TrackingGridDragSession: Equatable {
    let draggingId: UUID
    let startIndex: Int
    var currentIndex: Int
    let dragStartCenter: CGPoint
    var translation: CGSize = .zero

    var fingerCenter: CGPoint {
        CGPoint(
            x: dragStartCenter.x + translation.width,
            y: dragStartCenter.y + translation.height
        )
    }
}

enum TrackingGridReorderCoordinator {
    static func makeDragSession<Item: Identifiable>(
        for itemId: UUID,
        in items: [Item],
        metrics: TrackingGridLayoutMetrics
    ) -> TrackingGridDragSession? where Item.ID == UUID {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            return nil
        }

        return TrackingGridDragSession(
            draggingId: itemId,
            startIndex: index,
            currentIndex: index,
            dragStartCenter: metrics.cardCenter(at: index)
        )
    }

    static func reorder<Item>(
        _ items: [Item],
        from sourceIndex: Int,
        to targetIndex: Int
    ) -> [Item] {
        guard items.indices.contains(sourceIndex),
              items.indices.contains(targetIndex),
              sourceIndex != targetIndex else {
            return items
        }

        var updated = items
        let movedItem = updated.remove(at: sourceIndex)
        updated.insert(movedItem, at: targetIndex)
        return updated
    }
}
