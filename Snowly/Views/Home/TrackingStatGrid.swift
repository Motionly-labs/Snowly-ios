//
//  TrackingStatGrid.swift
//  Snowly
//
//  Draggable, editable stat widget grid for the active tracking dashboard.
//  Interactive reorder state stays local to this view while dragging; the
//  parent layout is only updated once on drop so persistence does not run in
//  the middle of the gesture.
//

import SwiftUI

struct TrackingStatGrid: View {

    private struct WiggleAnimationState: Equatable {
        let isActive: Bool
        let isEvenIndex: Bool
    }

    // MARK: Inputs

    let instances: [ActiveTrackingCardInstance]
    let snapshots: [UUID: ActiveTrackingCardSnapshot]
    let isEditing: Bool
    let cardsAppeared: Bool
    let onReorder: ([ActiveTrackingCardInstance]) -> Void
    let onRemove: (ActiveTrackingCardInstance) -> Void
    let onAdd: (ActiveTrackingCardKind) -> Void

    // MARK: State

    @State private var displayInstances: [ActiveTrackingCardInstance]
    @State private var dragSession: TrackingGridDragSession?
    @State private var gridWidth: CGFloat = 300

    private static let cardHeight: CGFloat = 88
    private static let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    init(
        instances: [ActiveTrackingCardInstance],
        snapshots: [UUID: ActiveTrackingCardSnapshot],
        isEditing: Bool,
        cardsAppeared: Bool,
        onReorder: @escaping ([ActiveTrackingCardInstance]) -> Void,
        onRemove: @escaping (ActiveTrackingCardInstance) -> Void,
        onAdd: @escaping (ActiveTrackingCardKind) -> Void
    ) {
        self.instances = instances
        self.snapshots = snapshots
        self.isEditing = isEditing
        self.cardsAppeared = cardsAppeared
        self.onReorder = onReorder
        self.onRemove = onRemove
        self.onAdd = onAdd
        _displayInstances = State(initialValue: instances)
    }

    private var layoutMetrics: TrackingGridLayoutMetrics {
        TrackingGridLayoutMetrics(
            gridWidth: gridWidth,
            cardHeight: Self.cardHeight,
            gutter: Spacing.gutter
        )
    }

    private var colWidth: CGFloat { layoutMetrics.columnWidth }

    private var hiddenGridKinds: [ActiveTrackingCardKind] {
        let presentKinds = Set(displayInstances.map(\.kind))
        return ActiveTrackingCardRegistry.allGridKinds.filter { !presentKinds.contains($0) }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: Spacing.gutter) {
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Self.gridColumns, spacing: Spacing.gutter) {
                    ForEach(Array(displayInstances.enumerated()), id: \.element.instanceId) { displayIndex, instance in
                        widgetCell(instance: instance, displayIndex: displayIndex)
                    }
                }
                .animation(AnimationTokens.gentleSpring, value: displayInstances.map(\.instanceId))

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
        .onChange(of: instances) { _, latest in
            guard dragSession == nil else { return }
            displayInstances = latest
        }
        .onChange(of: isEditing) { _, editing in
            guard !editing else { return }
            if dragSession != nil {
                commitDisplayOrderIfNeeded()
            }
            withAnimation(AnimationTokens.gentleSpring) {
                dragSession = nil
            }
        }
    }

    // MARK: - Floating Drag Card

    @ViewBuilder
    private var floatingDragCard: some View {
        if let dragSession,
           let instance = displayInstances.first(where: { $0.instanceId == dragSession.draggingId }) {
            statCardBody(instance: instance)
                .frame(width: colWidth, height: Self.cardHeight)
                .scaleEffect(1.05)
                .shadow(color: .black.opacity(Opacity.moderate), radius: 14, x: 0, y: 6)
                .position(
                    x: dragSession.fingerCenter.x,
                    y: dragSession.fingerCenter.y
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: - Widget Cell

    @ViewBuilder
    private func widgetCell(instance: ActiveTrackingCardInstance, displayIndex: Int) -> some View {
        let isDragging = dragSession?.draggingId == instance.instanceId
        let wiggleState = WiggleAnimationState(
            isActive: isEditing && !isDragging,
            isEvenIndex: displayIndex.isMultiple(of: 2)
        )

        statCardBody(instance: instance)
            .opacity(isDragging ? 0 : 1)
            .rotationEffect(
                wiggleState.isActive
                    ? .degrees(wiggleState.isEvenIndex ? 1.5 : -1.5)
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
                wiggleState.isActive
                    ? Animation.easeInOut(duration: 0.13)
                        .repeatForever(autoreverses: true)
                        .delay(wiggleState.isEvenIndex ? 0.0 : 0.07)
                    : AnimationTokens.quickEaseOut,
                value: wiggleState
            )
            .gesture(
                isEditing
                    ? DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            onDragChanged(
                                instanceId: instance.instanceId,
                                translation: value.translation
                            )
                        }
                        .onEnded { _ in
                            onDragEnded()
                        }
                    : nil
            )
    }

    // MARK: - Drag Logic

    private func onDragChanged(instanceId: UUID, translation: CGSize) {
        if dragSession == nil {
            guard let session = TrackingGridReorderCoordinator.makeDragSession(
                for: instanceId,
                in: displayInstances,
                metrics: layoutMetrics
            ) else {
                return
            }
            dragSession = session
            HapticFeedback.impact()
        }

        guard var session = dragSession, session.draggingId == instanceId else { return }
        session.translation = translation

        if let targetIndex = layoutMetrics.targetIndex(
            for: session.fingerCenter,
            itemCount: displayInstances.count,
            excluding: session.currentIndex
        ) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                displayInstances = TrackingGridReorderCoordinator.reorder(
                    displayInstances,
                    from: session.currentIndex,
                    to: targetIndex
                )
            }
            session.currentIndex = targetIndex
        }

        dragSession = session
    }

    private func onDragEnded() {
        commitDisplayOrderIfNeeded()
        withAnimation(AnimationTokens.gentleSpring) {
            dragSession = nil
        }
    }

    private func commitDisplayOrderIfNeeded() {
        guard displayInstances.map(\.instanceId) != instances.map(\.instanceId) else { return }
        onReorder(displayInstances)
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
                    .foregroundStyle(ColorTokens.secondaryAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.card)
            .padding(.vertical, Spacing.lg)
            .dashboardGridCardBackground(accent: ColorTokens.secondaryAccent)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        ColorTokens.secondaryAccent.opacity(Opacity.moderate),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

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
        case .skiing: return ColorTokens.skiingAccent
        case .lift:   return ColorTokens.liftAccent
        case .others: return ColorTokens.walkAccent
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
