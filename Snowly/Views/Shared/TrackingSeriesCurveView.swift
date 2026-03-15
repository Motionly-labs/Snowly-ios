//
//  TrackingSeriesCurveView.swift
//  Snowly
//
//  Unified rendering canvas for all active-tracking series cards.
//  Callers compute coordinates; this view owns fill, stroke, selection, and empty state.
//

import SwiftUI

/// Reusable curve canvas shared by all active-tracking series card types.
///
/// Visual contract enforced here:
/// - Bezier-smooth stroke via `CurveRendering.smoothPath`
/// - Consistent stroke weight (`CurveRendering.standardStrokeWidth`)
/// - `CurveRendering.smoothFillPath` area fill with a configurable gradient
/// - `CurveSelectionOverlay` on tap, with tint derived from the hit segment's state
/// - Dashed flat-line empty state when fewer than two points are provided
///
/// Coordinate normalisation is **intentionally left to callers** — each series card
/// has domain-specific scale semantics (fixed ceiling for live speed, min-max for
/// altitude/heart-rate).  Callers pass pre-computed `[CGPoint]` sized to their own
/// `GeometryReader` frame.
struct TrackingSeriesCurveView: View {

    // MARK: - Segment coloring

    /// Describes how to colour the bezier stroke.
    enum Coloring {
        /// Every segment uses the same colour.
        case uniform(Color)
        /// Segments are coloured by activity state. `states` must be parallel to `points`.
        case byState([SpeedCurveState], color: (SpeedCurveState) -> Color)

        /// The colour that applies at the given point index.
        func color(at index: Int) -> Color {
            switch self {
            case .uniform(let c):
                return c
            case .byState(let states, let colorFn):
                guard index < states.count else { return .primary }
                return colorFn(states[index])
            }
        }
    }

    // MARK: - Inputs

    /// Pre-computed, normalised coordinates fitted to the caller's frame.
    let points: [CGPoint]
    /// Stroke coloring strategy.
    let coloring: Coloring
    /// Gradient fill colours, top → bottom.  Typically `[tint.opacity(0.12), .clear]`.
    let fillColors: [Color]
    /// Stroke weight. Defaults to `CurveRendering.standardStrokeWidth`.
    var strokeWidth: CGFloat = CurveRendering.standardStrokeWidth
    /// Returns the label shown in the `CurveSelectionOverlay` for the tapped point.
    /// Pass `nil` to disable tap selection entirely.
    var selectionLabel: ((Int) -> String)?

    // MARK: - State

    @State private var selectedIndex: Int?

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            if points.count < 2 {
                emptyStateLine(width: geo.size.width, baseline: geo.size.height)
            } else {
                curveContent(size: geo.size)
                    .contentShape(Rectangle())
                    .simultaneousGesture(selectionLabel != nil ? selectionGesture : nil)
            }
        }
        .onChange(of: points.count) { _, _ in
            selectedIndex = nil
        }
    }

    // MARK: - Rendering

    private func curveContent(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            CurveRendering.smoothFillPath(points: points, baseline: size.height)
                .fill(LinearGradient(
                    colors: fillColors,
                    startPoint: .top,
                    endPoint: .bottom
                ))

            Canvas { context, _ in
                drawStrokes(into: &context)
            }

            if let idx = selectedIndex, idx < points.count, let label = selectionLabel?(idx) {
                CurveSelectionOverlay(
                    point: points[idx],
                    baseline: size.height,
                    label: label,
                    tint: coloring.color(at: idx),
                    chartSize: size
                )
            }
        }
    }

    private func emptyStateLine(width: CGFloat, baseline: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: baseline))
            path.addLine(to: CGPoint(x: width, y: baseline))
        }
        .stroke(
            Color.secondary.opacity(Opacity.muted),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    private func drawStrokes(into context: inout GraphicsContext) {
        let style = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        switch coloring {
        case .uniform(let color):
            context.stroke(CurveRendering.smoothPath(points: points), with: .color(color), style: style)
        case .byState(let states, let colorFn):
            CurveRendering.drawStateSegments(
                into: &context,
                points: points,
                states: states,
                stateColor: colorFn,
                style: style
            )
        }
    }

    // MARK: - Tap selection

    private var selectionGesture: some Gesture {
        SpatialTapGesture().onEnded { event in
            guard let hit = CurveRendering.nearestPointIndex(to: event.location.x, in: points) else { return }
            selectedIndex = selectedIndex == hit ? nil : hit
        }
    }
}
