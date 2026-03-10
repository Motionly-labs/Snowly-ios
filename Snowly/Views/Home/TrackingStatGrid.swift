//
//  TrackingStatGrid.swift
//  Snowly
//
//  Draggable, editable stat widget grid for the active tracking dashboard.
//  Mirrors the iOS home screen widget editing interaction:
//  long-press enters edit mode, cards wiggle and expose delete controls,
//  dragging reorders in real time using positional hit-testing.
//
//  Drag implementation uses a floating overlay strategy to prevent jitter:
//  the dragging card is removed from grid flow (opacity 0) and rendered as
//  an absolutely-positioned overlay at `dragStartCenter + translation`.
//  This decouples the drag-card's visual position from its index in the
//  array, eliminating the offset jump that occurred when the array reordered
//  mid-drag under the old offset-from-naturalCenter approach.
//

import SwiftUI

struct TrackingStatGrid: View {

    // MARK: Inputs

    @Binding var gridInstances: [ActiveTrackingCardInstance]
    let snapshots: [UUID: ActiveTrackingCardSnapshot]
    let isEditing: Bool
    let cardsAppeared: Bool
    let onRemove: (ActiveTrackingCardInstance) -> Void
    let onAdd: (ActiveTrackingCardKind) -> Void

    // MARK: Drag State

    @State private var draggingId: UUID? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var dragStartCenter: CGPoint = .zero
    @GestureState private var dragGestureActive: Bool = false

    // MARK: Layout

    @State private var gridWidth: CGFloat = 300

    // MARK: Wiggle

    @State private var wigglePhase: Bool = false

    private static let cardHeight: CGFloat = 88
    private static let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var colWidth: CGFloat { (gridWidth - Spacing.gutter) / 2 }

    private var hiddenGridKinds: [ActiveTrackingCardKind] {
        let presentKinds = Set(gridInstances.map(\.kind))
        return ActiveTrackingCardRegistry.allGridKinds.filter { !presentKinds.contains($0) }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: Spacing.gutter) {
            // ZStack hosts both the grid and the floating drag card.
            // The floating card is a direct ZStack child so it shares the
            // same coordinate origin as the grid, letting cardCenter(at:)
            // feed directly into .position().
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Self.gridColumns, spacing: Spacing.gutter) {
                    ForEach(Array(gridInstances.enumerated()), id: \.element.instanceId) { displayIndex, instance in
                        widgetCell(instance: instance, displayIndex: displayIndex)
                    }
                }
                .animation(AnimationTokens.gentleSpring, value: gridInstances.map(\.instanceId))

                floatingDragCard
            }

            if isEditing && !hiddenGridKinds.isEmpty {
                addTray
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { gridWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in gridWidth = w }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                wigglePhase = true
            } else {
                withAnimation(AnimationTokens.quickEaseOut) {
                    wigglePhase = false
                }
                withAnimation(AnimationTokens.gentleSpring) {
                    draggingId = nil
                    dragTranslation = .zero
                }
            }
        }
        .onChange(of: dragGestureActive) { _, active in
            guard !active else { return }
            withAnimation(AnimationTokens.gentleSpring) {
                draggingId = nil
                dragTranslation = .zero
            }
        }
    }

    // MARK: - Floating Drag Card

    /// The card currently being dragged, rendered at absolute position.
    /// Positioned via .position() so its center tracks the finger exactly,
    /// independent of any reordering happening in the grid below.
    @ViewBuilder
    private var floatingDragCard: some View {
        if let dragId = draggingId,
           let instance = gridInstances.first(where: { $0.instanceId == dragId }) {
            statCardBody(instance: instance)
                .frame(width: colWidth, height: Self.cardHeight)
                .scaleEffect(1.05)
                .shadow(color: .black.opacity(Opacity.moderate), radius: 14, x: 0, y: 6)
                .position(
                    x: dragStartCenter.x + dragTranslation.width,
                    y: dragStartCenter.y + dragTranslation.height
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: - Widget Cell

    @ViewBuilder
    private func widgetCell(instance: ActiveTrackingCardInstance, displayIndex: Int) -> some View {
        let isDragging = draggingId == instance.instanceId
        let isEvenIndex = displayIndex.isMultiple(of: 2)

        statCardBody(instance: instance)
            // Hidden in grid while floating — preserves its slot so siblings
            // animate into the correct gap position during live reorder.
            .opacity(isDragging ? 0 : 1)
            // Drive rotationEffect from wigglePhase, not isEditing.
            // This ensures the target value AND the animation fire in the same
            // render pass when wigglePhase → false, so quickEaseOut can
            // interrupt the in-flight repeatForever. If isEditing were used
            // instead, isEditing changes to false first (zeroing the target),
            // then wigglePhase changes — but the target is already zero so
            // SwiftUI sees no delta and never fires the interrupting animation.
            .rotationEffect(
                wigglePhase && !isDragging
                    ? .degrees(isEvenIndex ? 1.5 : -1.5)
                    : .zero
            )
            .overlay(alignment: .topLeading) {
                if isEditing && !isDragging {
                    deleteButton(for: instance)
                        .offset(x: -Spacing.sm, y: -Spacing.sm)
                        .transition(.scale(scale: 0.1, anchor: .topLeading).combined(with: .opacity))
                }
            }
            .animation(
                wigglePhase && !isDragging
                    ? Animation.easeInOut(duration: 0.13)
                        .repeatForever(autoreverses: true)
                        .delay(isEvenIndex ? 0.0 : 0.07)
                    : AnimationTokens.quickEaseOut,
                value: wigglePhase
            )
            .gesture(
                isEditing
                    ? DragGesture(minimumDistance: 4)
                        .updating($dragGestureActive) { _, state, _ in state = true }
                        .onChanged { value in
                            onDragChanged(instance: instance, translation: value.translation)
                        }
                        .onEnded { _ in
                            withAnimation(AnimationTokens.gentleSpring) {
                                draggingId = nil
                                dragTranslation = .zero
                            }
                        }
                    : nil
            )
    }

    // MARK: - Drag Logic

    private func onDragChanged(instance: ActiveTrackingCardInstance, translation: CGSize) {
        if draggingId == nil {
            guard let idx = gridInstances.firstIndex(where: { $0.instanceId == instance.instanceId }) else { return }
            draggingId = instance.instanceId
            dragStartCenter = cardCenter(at: idx)
            HapticFeedback.impact()
        }
        guard draggingId == instance.instanceId else { return }

        // Update translation — the floating card reads this directly,
        // so its visual position is always dragStartCenter + translation.
        dragTranslation = translation

        let fingerCenter = CGPoint(
            x: dragStartCenter.x + translation.width,
            y: dragStartCenter.y + translation.height
        )
        guard let currentIdx = gridInstances.firstIndex(where: { $0.instanceId == instance.instanceId }) else { return }
        guard let targetIdx = computeTargetIndex(at: fingerCenter, excluding: currentIdx) else { return }

        // Reorder the array — only non-dragging cards animate (dragging card
        // is opacity-0 in the grid, so its slot shifts without visual artifact).
        withAnimation(AnimationTokens.gentleSpring) {
            var updated = gridInstances
            updated.move(
                fromOffsets: IndexSet(integer: currentIdx),
                toOffset: targetIdx > currentIdx ? targetIdx + 1 : targetIdx
            )
            gridInstances = updated
        }
    }

    private func computeTargetIndex(at position: CGPoint, excluding sourceIdx: Int) -> Int? {
        let rowHeight = Self.cardHeight + Spacing.gutter
        let totalColWidth = colWidth * 2 + Spacing.gutter
        let col = position.x > totalColWidth / 2 ? 1 : 0
        let maxRow = (gridInstances.count - 1) / 2
        let row = max(0, min(Int(position.y / rowHeight), maxRow))
        let candidate = min(row * 2 + col, gridInstances.count - 1)
        return candidate != sourceIdx ? candidate : nil
    }

    private func cardCenter(at index: Int) -> CGPoint {
        let rowHeight = Self.cardHeight + Spacing.gutter
        let col = index % 2
        let row = index / 2
        let x = col == 0 ? colWidth / 2 : colWidth + Spacing.gutter + colWidth / 2
        let y = CGFloat(row) * rowHeight + Self.cardHeight / 2
        return CGPoint(x: x, y: y)
    }

    // MARK: - Stat Card

    @ViewBuilder
    private func cardHeader(for kind: ActiveTrackingCardKind) -> some View {
        let def = ActiveTrackingCardRegistry.definition(for: kind)
        HStack(spacing: Spacing.xs) {
            Image(systemName: def.icon)
                .font(Typography.caption2Semibold)
            Text(String(localized: String.LocalizationValue(def.titleKey)))
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func statCardBody(instance: ActiveTrackingCardInstance) -> some View {
        switch snapshots[instance.instanceId] {
        case .scalar(let s):
            numberStatCard(snapshot: s)
        case .series(let s):
            seriesCard(snapshot: s, instance: instance)
        case .profile, .text, .heartRateSeries, nil:
            EmptyView()
        }
    }

    private func numberStatCard(snapshot: ScalarCardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gutter) {
            cardHeader(for: snapshot.kind)

            AnimatedNumberText(
                value: snapshot.value,
                decimals: snapshot.decimals,
                suffix: snapshot.unit,
                delay: snapshot.animationDelay
            )
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.lg)
        .dashboardGridCardBackground()
        .opacity(cardsAppeared ? 1 : 0)
        .scaleEffect(cardsAppeared ? 1 : 0.92)
        .animation(
            AnimationTokens.smoothEntranceFast.delay(snapshot.animationDelay),
            value: cardsAppeared
        )
    }

    private func seriesCard(snapshot: SeriesCardSnapshot, instance: ActiveTrackingCardInstance) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            cardHeader(for: snapshot.kind)

            AltitudeSparkline(samples: snapshot.samples)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.lg)
        .dashboardGridCardBackground()
        .opacity(cardsAppeared ? 1 : 0)
        .scaleEffect(cardsAppeared ? 1 : 0.92)
        .animation(AnimationTokens.smoothEntranceFast, value: cardsAppeared)
    }

    // MARK: - Delete Button

    private func deleteButton(for instance: ActiveTrackingCardInstance) -> some View {
        Button {
            withAnimation(AnimationTokens.standardEaseInOut) {
                onRemove(instance)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(ColorTokens.brandRed)
                    .frame(width: 22, height: 22)
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Tray

    private var addTray: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "tracking_edit_add_stats"))
                .font(Typography.caption2Semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.top, Spacing.xs)

            LazyVGrid(columns: Self.gridColumns, spacing: Spacing.gutter) {
                ForEach(hiddenGridKinds, id: \.rawValue) { kind in
                    addableCard(kind)
                }
            }
        }
    }

    private func addableCard(_ kind: ActiveTrackingCardKind) -> some View {
        Button {
            withAnimation(AnimationTokens.gentleSpring) {
                onAdd(kind)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.gutter) {
                cardHeader(for: kind)

                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ColorTokens.brandWarmAmber)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.card)
            .padding(.vertical, Spacing.lg)
            .dashboardGridCardBackground(accent: ColorTokens.brandWarmAmber)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        ColorTokens.brandWarmAmber.opacity(Opacity.moderate),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Wiggle

    // Wiggle is driven by wigglePhase via .animation(value: wigglePhase) on each cell.
    // Both rotationEffect target and animation condition use wigglePhase (not isEditing),
    // so the target change and the animation interruption are always in the same render pass.

}

// MARK: - Altitude Sparkline

/// Live, segmented altitude sparkline used by the altitudeCurve widget card.
struct AltitudeSparkline: View {
    let samples: [AltitudeSample]
    let unitLabel: String

    @State private var selectedSampleTime: Date?

    init(samples: [AltitudeSample], unitLabel: String = "") {
        self.samples = samples
        self.unitLabel = unitLabel
    }

    private func color(for state: SpeedCurveState) -> Color {
        switch state {
        case .skiing: return ColorTokens.brandIceBlue
        case .lift:   return ColorTokens.brandWarmAmber
        case .others: return Color.secondary.opacity(0.85)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            if samples.count < 2 {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                }
                .stroke(
                    Color.secondary.opacity(Opacity.muted),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            } else {
                let pts = computePoints(size: size)
                let selectionIndex = selectedIndex
                ZStack {
                    CurveRendering.smoothFillPath(points: pts, baseline: size.height)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))

                    Canvas { context, _ in
                        drawSegments(into: context, pts: pts)
                    }

                    if let selectionIndex, selectionIndex < pts.count {
                        CurveSelectionOverlay(
                            point: pts[selectionIndex],
                            baseline: size.height,
                            label: selectionLabel(for: samples[selectionIndex]),
                            tint: color(for: samples[selectionIndex].state),
                            chartSize: size
                        )
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        selectPoint(at: value.location.x, points: pts)
                    }
                )
            }
        }
        .onChange(of: samples.map(\.time)) { _, latestTimes in
            guard let selectedSampleTime else { return }
            if !latestTimes.contains(selectedSampleTime) {
                self.selectedSampleTime = nil
            }
        }
    }

    private func computePoints(size: CGSize) -> [CGPoint] {
        let altitudes = samples.map(\.altitude)
        let minAlt = altitudes.min() ?? 0
        let maxAlt = altitudes.max() ?? 1
        let range = max(maxAlt - minAlt, 20)

        return samples.enumerated().map { idx, sample in
            let x = size.width * CGFloat(idx) / CGFloat(samples.count - 1)
            let normalised = (sample.altitude - minAlt) / range
            let y = size.height * (1.0 - CGFloat(normalised)) * 0.85 + 4
            return CGPoint(x: x, y: y)
        }
    }

    private var selectedIndex: Int? {
        guard let selectedSampleTime else { return nil }
        return samples.firstIndex(where: { $0.time == selectedSampleTime })
    }

    private func drawSegments(into context: GraphicsContext, pts: [CGPoint]) {
        guard pts.count >= 2 else { return }

        let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        var segStart = 1
        while segStart < pts.count {
            let segState = samples[segStart].state
            var j = segStart
            while j < pts.count && samples[j].state == segState {
                j += 1
            }
            let segPath = CurveRendering.smoothPath(points: Array(pts[(segStart - 1)..<j]))
            context.stroke(segPath, with: .color(color(for: segState)), style: strokeStyle)
            segStart = j
        }
    }

    private func selectionLabel(for sample: AltitudeSample) -> String {
        let value = String(format: "%.0f", sample.altitude)
        return unitLabel.isEmpty ? value : "\(value) \(unitLabel)"
    }

    private func selectPoint(at x: CGFloat, points: [CGPoint]) {
        guard let index = CurveRendering.nearestPointIndex(to: x, in: points) else { return }
        let tappedTime = samples[index].time
        selectedSampleTime = selectedSampleTime == tappedTime ? nil : tappedTime
    }
}
