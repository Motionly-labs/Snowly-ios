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

    // MARK: Inputs

    let instances: [ActiveTrackingCardInstance]
    let inputs: [UUID: AnyActiveTrackingCardInput]
    let isEditing: Bool
    let cardsAppeared: Bool
    let onReorder: ([ActiveTrackingCardInstance]) -> Void
    let onRemove: (ActiveTrackingCardInstance) -> Void
    let onAdd: (ActiveTrackingCardKind) -> Void

    // MARK: State

    @State private var displayInstances: [ActiveTrackingCardInstance]
    @State private var dragSession: TrackingGridDragSession?
    @State private var gridWidth: CGFloat = 300
    @State private var wiggleBeat = false
    @State private var wiggleLoopTask: Task<Void, Never>?

    private static let cardHeight: CGFloat = 88
    private static let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    init(
        instances: [ActiveTrackingCardInstance],
        inputs: [UUID: AnyActiveTrackingCardInput],
        isEditing: Bool,
        cardsAppeared: Bool,
        onReorder: @escaping ([ActiveTrackingCardInstance]) -> Void,
        onRemove: @escaping (ActiveTrackingCardInstance) -> Void,
        onAdd: @escaping (ActiveTrackingCardKind) -> Void
    ) {
        self.instances = instances
        self.inputs = inputs
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
            if editing {
                startWiggleLoop()
            } else {
                stopWiggleLoop()
                if dragSession != nil {
                    commitDisplayOrderIfNeeded()
                }
                withAnimation(AnimationTokens.gentleSpring) {
                    dragSession = nil
                }
            }
        }
        .onAppear {
            if isEditing {
                startWiggleLoop()
            }
        }
        .onDisappear {
            stopWiggleLoop()
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

        statCardBody(instance: instance)
            .opacity(isDragging ? 0 : 1)
            .rotationEffect(wiggleAngle(for: displayIndex, isDragging: isDragging))
            .overlay(alignment: .topLeading) {
                if isEditing && !isDragging {
                    deleteButton(for: instance)
                        .offset(x: -Spacing.sm, y: -Spacing.sm)
                        .transition(.scale(scale: 0.1, anchor: .topLeading).combined(with: .opacity))
                }
            }
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

    private func wiggleAngle(for displayIndex: Int, isDragging: Bool) -> Angle {
        guard isEditing && !isDragging else { return .zero }

        let slotDirection = displayIndex.isMultiple(of: 2) ? 1.0 : -1.0
        let beatDirection = wiggleBeat ? 1.0 : -1.0
        return .degrees(slotDirection * beatDirection * 1.4)
    }

    @MainActor
    private func startWiggleLoop() {
        guard wiggleLoopTask == nil else { return }

        wiggleLoopTask = Task { @MainActor in
            var nextBeat = true

            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.13)) {
                    wiggleBeat = nextBeat
                }
                nextBeat.toggle()
                try? await Task.sleep(for: .milliseconds(130))
            }
        }
    }

    @MainActor
    private func stopWiggleLoop() {
        wiggleLoopTask?.cancel()
        wiggleLoopTask = nil

        withAnimation(AnimationTokens.quickEaseOut) {
            wiggleBeat = false
        }
    }

    // MARK: - Stat Card

    @ViewBuilder
    private func cardHeader(for kind: ActiveTrackingCardKind) -> some View {
        let def = ActiveTrackingCardRegistry.definition(for: kind)
        let accent = cardAccent(for: kind)

        HStack(spacing: Spacing.sm) {
            Image(systemName: def.icon)
                .font(Typography.caption2Semibold)
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(accent.opacity(0.14))
                )
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                }
            Text(String(localized: String.LocalizationValue(def.titleKey)))
                .font(Typography.caption2Semibold)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statCardBody(instance: ActiveTrackingCardInstance) -> some View {
        switch inputs[instance.instanceId] {
        case .scalar(let input):
            scalarStatCard(input: input)
        case .series(let input):
            seriesCard(input: input)
        case .composite, nil:
            EmptyView()
        }
    }

    private func scalarStatCard(input: ActiveTrackingScalarCardInput) -> some View {
        gridCardShell(accent: cardAccent(for: input.kind)) {
            VStack(alignment: .leading, spacing: Spacing.gutter) {
                cardHeader(for: input.kind)

                scalarValueView(input.primaryValue)
            }
        }
        .opacity(cardsAppeared ? 1 : 0)
        .scaleEffect(cardsAppeared ? 1 : 0.92)
        .animation(
            AnimationTokens.smoothEntranceFast.delay(animationDelay(for: input.primaryValue)),
            value: cardsAppeared
        )
    }

    @ViewBuilder
    private func scalarValueView(_ value: ActiveTrackingCardPrimaryValue) -> some View {
        switch value {
        case .numeric(let numeric):
            AnimatedNumberText(
                value: numeric.value,
                decimals: numeric.decimals,
                suffix: numeric.unit,
                delay: numeric.animationDelay
            )
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        case .text(let text):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(text.value)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if !text.unit.isEmpty {
                    Text(text.unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func animationDelay(for value: ActiveTrackingCardPrimaryValue) -> Double {
        switch value {
        case .numeric(let numeric):
            numeric.animationDelay
        case .text:
            0
        }
    }

    private func seriesCard(input: ActiveTrackingSeriesCardInput) -> some View {
        gridCardShell(accent: cardAccent(for: input.kind)) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                cardHeader(for: input.kind)

                seriesContent(payload: input.seriesPayload)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(cardsAppeared ? 1 : 0)
        .scaleEffect(cardsAppeared ? 1 : 0.92)
        .animation(AnimationTokens.smoothEntranceFast, value: cardsAppeared)
    }

    @ViewBuilder
    private func seriesContent(payload: ActiveTrackingSeriesPayload) -> some View {
        switch payload {
        case .altitude(let samples):
            AltitudeSparkline(samples: samples)
        case .heartRate, .speed:
            EmptyView()
        }
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
            gridCardShell(accent: cardAccent(for: kind)) {
                VStack(alignment: .leading, spacing: Spacing.gutter) {
                    cardHeader(for: kind)

                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(cardAccent(for: kind))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        cardAccent(for: kind).opacity(Opacity.moderate),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gridCardShell<Content: View>(
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.card)
            .padding(.vertical, Spacing.lg)
            .dashboardGridCardBackground(accent: accent)
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1.1)
                }
            }
    }

    private func cardAccent(for kind: ActiveTrackingCardKind) -> Color {
        switch kind {
        case .currentSpeed, .speedCurve, .skiTime:
            return ColorTokens.sportAccent
        case .peakSpeed, .liftCount:
            return ColorTokens.secondaryAccent
        case .avgSpeed, .distance:
            return ColorTokens.info
        case .vertical:
            return ColorTokens.success
        case .runCount:
            return ColorTokens.brandGold
        case .currentAltitude, .altitudeCurve:
            return ColorTokens.trailBlack
        case .heartRate, .heartRateCurve:
            return ColorTokens.brandRed
        }
    }

}

// MARK: - Altitude Sparkline

/// Live, segmented altitude sparkline used by the altitudeCurve widget card.
struct AltitudeSparkline: View {
    let samples: [AltitudeSample]
    var unitLabel: String = ""

    private var displaySamples: [AltitudeSample] {
        samples.droppingLeadingZeroLikeSamples()
    }

    var body: some View {
        let s = displaySamples
        GeometryReader { geo in
            TrackingSeriesCurveView(
                points: CurveRendering.indexedPoints(
                    values: s.map(\.altitude),
                    in: geo.size,
                    minimumRange: 20
                ),
                coloring: .byState(s.map(\.state)) { $0.trackingColor },
                fillColors: [
                    .white.opacity(CurveRendering.standardFillTopOpacity),
                    .white.opacity(0),
                ],
                selectionLabel: { [s, unitLabel] idx in
                    guard idx < s.count else { return "--" }
                    let formatted = String(format: "%.0f", s[idx].altitude)
                    return unitLabel.isEmpty ? formatted : "\(formatted) \(unitLabel)"
                }
            )
        }
    }
}
