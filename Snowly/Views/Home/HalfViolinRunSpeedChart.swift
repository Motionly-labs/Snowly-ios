//
//  HalfViolinRunSpeedChart.swift
//  Snowly
//
//  Single-sided violin chart for per-run speed distributions.
//

import SwiftUI

struct HalfViolinRunSpeedChart: View {
    struct RunDistribution: Identifiable {
        let id: UUID
        let label: String
        let samples: [Double]
        let min: Double
        let max: Double
        let mean: Double
        let bins: [Double]
        let distanceText: String?
        let durationText: String?
        let verticalText: String?
    }

    let runs: [RunDistribution]
    let unitLabel: String

    @State private var selectedID: UUID?

    private let yTicks: Int = 4
    private let slotWidth: CGFloat = 74
    private let labelHeight: CGFloat = 30

    private var activeID: UUID? {
        selectedID ?? runs.first?.id
    }

    private var speedRange: ClosedRange<Double> {
        let minValue = runs.map(\.min).min() ?? 0
        let maxValue = runs.map(\.max).max() ?? 1
        let paddedMin = floor(max(0, minValue - 2))
        let paddedMax = ceil(max(paddedMin + 1, maxValue + 2))
        return paddedMin...paddedMax
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            chartCanvas
                .frame(height: 236)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))

            if let selected = selectedRun {
                runDetailCard(selected)
            }
        }
        .onAppear {
            if selectedID == nil {
                selectedID = runs.first?.id
            }
        }
    }

    private var selectedRun: RunDistribution? {
        guard let activeID else { return nil }
        return runs.first { $0.id == activeID }
    }

    private var chartCanvas: some View {
        GeometryReader { geo in
            let chartInsets = EdgeInsets(top: Spacing.md, leading: Spacing.md, bottom: Spacing.xs, trailing: Spacing.md)
            let chartAreaHeight = max(geo.size.height - labelHeight, 1)
            let contentWidth = max(
                geo.size.width,
                chartInsets.leading + chartInsets.trailing + CGFloat(runs.count) * slotWidth
            )
            let plotRect = CGRect(
                x: chartInsets.leading,
                y: chartInsets.top,
                width: max(contentWidth - chartInsets.leading - chartInsets.trailing, 1),
                height: max(chartAreaHeight - chartInsets.top - chartInsets.bottom, 1)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            drawGrid(context: &context, in: plotRect)

                            for (index, run) in runs.enumerated() {
                                let isActive = activeID == nil || run.id == activeID
                                drawRun(
                                    run,
                                    at: index,
                                    total: runs.count,
                                    slotWidth: slotWidth,
                                    in: plotRect,
                                    isActive: isActive,
                                    context: &context
                                )
                            }
                        }
                        .frame(width: contentWidth, height: chartAreaHeight)

                        HStack(spacing: 0) {
                            ForEach(runs) { run in
                                Color.clear
                                    .frame(width: slotWidth, height: plotRect.height)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(AnimationTokens.quickEaseOut) {
                                            selectedID = run.id
                                        }
                                    }
                                    .accessibilityLabel(run.label)
                                    .accessibilityAddTraits(activeID == run.id ? .isSelected : [])
                            }
                        }
                        .padding(.leading, chartInsets.leading)
                        .padding(.top, chartInsets.top)
                    }

                    xLabels(insetLeading: chartInsets.leading, contentWidth: contentWidth)
                        .frame(height: labelHeight)
                }
                .frame(width: contentWidth, height: geo.size.height, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func xLabels(insetLeading: CGFloat, contentWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(runs) { run in
                Text(run.label)
                    .font(.caption2.weight(activeID == run.id ? .semibold : .regular))
                    .foregroundStyle(activeID == run.id ? .primary : .secondary)
                    .frame(width: slotWidth)
            }
        }
        .padding(.leading, insetLeading)
        .frame(width: contentWidth, alignment: .leading)
    }

    private func runDetailCard(_ run: RunDistribution) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(run.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: String(localized: "chart_sample_count_format"), Int64(run.samples.count)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.sm) {
                summaryMetric(title: String(localized: "chart_stat_min"), value: "\(Int(run.min.rounded()))", unit: unitLabel, emphasized: false)
                summaryMetric(title: String(localized: "chart_stat_mean"), value: "\(Int(run.mean.rounded()))", unit: unitLabel, emphasized: true)
                summaryMetric(title: String(localized: "chart_stat_max"), value: "\(Int(run.max.rounded()))", unit: unitLabel, emphasized: false)
            }

            HStack(spacing: Spacing.xs) {
                if let distanceText = run.distanceText {
                    runMetaText(title: String(localized: "common_distance"), value: distanceText)
                }
                if let durationText = run.durationText {
                    runMetaText(title: String(localized: "common_duration"), value: durationText)
                }
                if let verticalText = run.verticalText {
                    runMetaText(title: String(localized: "common_vertical"), value: verticalText)
                }
            }
        }
        .padding(Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
    }

    private func summaryMetric(
        title: String,
        value: String,
        unit: String,
        emphasized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(.body.weight(emphasized ? .bold : .semibold))
                    .foregroundStyle(emphasized ? .primary : .secondary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
    }

    private func runMetaText(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func drawGrid(context: inout GraphicsContext, in rect: CGRect) {
        for tick in 0...yTicks {
            let t = Double(tick) / Double(yTicks)
            let speed = speedRange.lowerBound + t * (speedRange.upperBound - speedRange.lowerBound)
            let y = yPosition(for: speed, in: rect)

            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: y))
            line.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(
                line,
                with: .color(
                    Color.primary.opacity(
                        tick == 0 ? ChartTokens.HalfViolin.baselineOpacity : ChartTokens.HalfViolin.gridLineOpacity
                    )
                ),
                style: StrokeStyle(lineWidth: tick == 0 ? 1 : 0.6)
            )
        }
    }

    private func drawRun(
        _ run: RunDistribution,
        at index: Int,
        total: Int,
        slotWidth: CGFloat,
        in rect: CGRect,
        isActive: Bool,
        context: inout GraphicsContext
    ) {
        guard total > 0 else { return }

        let slotStartX = rect.minX + CGFloat(index) * slotWidth
        let axisX = slotStartX + slotWidth * 0.42
        let maxHalfWidth = min(24, slotWidth * 0.44)
        let alpha: Double = isActive ? ChartTokens.HalfViolin.selectedAlpha : ChartTokens.HalfViolin.dimmedAlpha
        let runColor = RunColorPalette.color(forRunIndex: index, totalRuns: total)

        let minY = yPosition(for: run.min, in: rect)
        let maxY = yPosition(for: run.max, in: rect)
        let meanY = yPosition(for: run.mean, in: rect)

        var rangePath = Path()
        rangePath.move(to: CGPoint(x: axisX, y: minY))
        rangePath.addLine(to: CGPoint(x: axisX, y: maxY))
        context.stroke(
            rangePath,
            with: .color(Color.primary.opacity(0.34 * alpha)),
            style: StrokeStyle(
                lineWidth: isActive
                    ? ChartTokens.HalfViolin.axisLineWidthSelected
                    : ChartTokens.HalfViolin.axisLineWidthDimmed,
                lineCap: .round
            )
        )

        let violinPath = halfViolinPath(
            bins: run.bins,
            axisX: axisX,
            maxWidth: maxHalfWidth,
            minY: minY,
            maxY: maxY
        )
        context.fill(
            violinPath,
            with: .linearGradient(
                Gradient(colors: [
                    runColor.opacity(ChartTokens.HalfViolin.violinFillTopOpacity * alpha),
                    runColor.opacity(ChartTokens.HalfViolin.violinFillBottomOpacity * alpha),
                ]),
                startPoint: CGPoint(x: axisX, y: maxY),
                endPoint: CGPoint(x: axisX + maxHalfWidth, y: minY)
            )
        )
        context.stroke(
            violinPath,
            with: .color(runColor.opacity(ChartTokens.HalfViolin.violinStrokeOpacity * alpha)),
            style: StrokeStyle(lineWidth: ChartTokens.HalfViolin.violinStrokeWidth)
        )

        let markerRadius: CGFloat = isActive
            ? ChartTokens.HalfViolin.meanRadiusSelected
            : ChartTokens.HalfViolin.meanRadiusDimmed
        let markerRect = CGRect(
            x: axisX - markerRadius,
            y: meanY - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        )
        context.fill(Path(ellipseIn: markerRect), with: .color(Color.white.opacity(0.96 * alpha)))
        context.stroke(
            Path(ellipseIn: markerRect),
            with: .color(runColor.opacity(alpha)),
            style: StrokeStyle(lineWidth: ChartTokens.HalfViolin.meanStrokeWidth)
        )
    }

    private func halfViolinPath(
        bins: [Double],
        axisX: CGFloat,
        maxWidth: CGFloat,
        minY: CGFloat,
        maxY: CGFloat
    ) -> Path {
        guard bins.count >= 2 else { return Path() }

        var path = Path()
        let range = max(minY - maxY, 1)

        path.move(to: CGPoint(x: axisX, y: maxY))

        for idx in 0..<bins.count {
            let t = CGFloat(idx) / CGFloat(bins.count - 1)
            let y = maxY + t * range
            let width = maxWidth * CGFloat(max(0, bins[idx]))
            path.addLine(to: CGPoint(x: axisX + width, y: y))
        }

        path.addLine(to: CGPoint(x: axisX, y: minY))
        path.closeSubpath()
        return path
    }

    private func yPosition(for speed: Double, in rect: CGRect) -> CGFloat {
        let range = speedRange.upperBound - speedRange.lowerBound
        guard range > 0 else { return rect.maxY }
        let t = (speed - speedRange.lowerBound) / range
        return rect.maxY - CGFloat(t) * rect.height
    }
}

extension HalfViolinRunSpeedChart.RunDistribution {
    static func fromSamples(
        id: UUID = UUID(),
        label: String,
        samples: [Double],
        distanceText: String? = nil,
        durationText: String? = nil,
        verticalText: String? = nil
    ) -> Self {
        let cleaned = samples.map { Swift.min(Swift.max($0, 0), 140) }.sorted()
        let minValue = cleaned.min() ?? 0
        let maxValue = cleaned.max() ?? 0
        let mean = cleaned.isEmpty ? 0 : cleaned.reduce(0, +) / Double(cleaned.count)
        let bins = smoothedDensityBins(samples: cleaned, binCount: 36)

        return Self(
            id: id,
            label: label,
            samples: cleaned,
            min: minValue,
            max: maxValue,
            mean: mean,
            bins: bins,
            distanceText: distanceText,
            durationText: durationText,
            verticalText: verticalText
        )
    }

    private static func smoothedDensityBins(samples: [Double], binCount: Int) -> [Double] {
        guard !samples.isEmpty, binCount > 1 else {
            return Array(repeating: 0, count: Swift.max(binCount, 2))
        }

        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 1
        let span = Swift.max(maxV - minV, 0.001)
        let bandwidth = Swift.max(span / 10, 1.2)
        let step = span / Double(binCount - 1)

        var bins = Array(repeating: 0.0, count: binCount)
        for i in 0..<binCount {
            let x = minV + Double(i) * step
            var density = 0.0
            for sample in samples {
                let z = (x - sample) / bandwidth
                density += exp(-0.5 * z * z)
            }
            bins[i] = density
        }

        let maxBin = bins.max() ?? 1
        guard maxBin > 0 else { return bins }
        return bins.map { $0 / maxBin }
    }
}

enum MockRunSpeedGenerator {
    static func generateFiveRuns() -> [HalfViolinRunSpeedChart.RunDistribution] {
        [
            makeRun(label: "Run 1", count: 138, profile: .stableCruise),
            makeRun(label: "Run 2", count: 152, profile: .peakBurst),
            makeRun(label: "Run 3", count: 126, profile: .volatile),
            makeRun(label: "Run 4", count: 160, profile: .fastSustained),
            makeRun(label: "Run 5", count: 118, profile: .technical),
        ]
    }

    static func distributions(from runs: [SkiRun], unitSystem: UnitSystem) -> [HalfViolinRunSpeedChart.RunDistribution] {
        var runNumber = 0
        return runs.compactMap { run in
            let samplesMs = run.trackPoints.map(\.speed)
            // Require at least 10 GPS samples — aligned with the 15s minimum run duration
            // at ~1 Hz, with headroom for GPS dropouts.
            guard samplesMs.count >= 10 else { return nil }
            runNumber += 1

            let converted: [Double] = samplesMs.map {
                switch unitSystem {
                case .metric: return UnitConversion.metersPerSecondToKmh($0)
                case .imperial: return UnitConversion.metersPerSecondToMph($0)
                }
            }

            let runTitleFormat = String(localized: "session_run_title_format")
            return .fromSamples(
                label: String(format: runTitleFormat, locale: Locale.current, Int64(runNumber)),
                samples: converted,
                distanceText: Formatters.distance(run.distance, unit: unitSystem),
                durationText: Formatters.duration(run.duration),
                verticalText: Formatters.vertical(run.verticalDrop, unit: unitSystem)
            )
        }
    }

    private enum Profile {
        case stableCruise
        case peakBurst
        case volatile
        case fastSustained
        case technical
    }

    private static func makeRun(
        label: String,
        count: Int,
        profile: Profile
    ) -> HalfViolinRunSpeedChart.RunDistribution {
        let values = (0..<count).map { index -> Double in
            let t = Double(index) / Double(max(count - 1, 1))
            let envelope = t * t * (3 - 2 * t)
            let wave = sin(t * .pi * 8) * 1.4 + sin(t * .pi * 2.8 + 0.4) * 1.8

            let raw: Double
            switch profile {
            case .stableCruise:
                let base = 28 + envelope * 13
                raw = base + wave * 0.85 + localBoost(t, center: 0.62, width: 0.11, gain: 6.5)
            case .peakBurst:
                let base = 24 + envelope * 18
                raw = base + wave * 0.9 + localBoost(t, center: 0.74, width: 0.08, gain: 18)
            case .volatile:
                let base = 22 + envelope * 16
                raw = base + sin(t * .pi * 14 + 0.2) * 5.8 + wave * 1.2
                    + localBoost(t, center: 0.42, width: 0.1, gain: 9)
            case .fastSustained:
                let base = 36 + envelope * 19
                raw = base + sin(t * .pi * 6.4) * 2.1 + localBoost(t, center: 0.55, width: 0.2, gain: 7.5)
            case .technical:
                let base = 20 + envelope * 17
                raw = base + sin(t * .pi * 12.5 + 0.8) * 4.2
                    + localBoost(t, center: 0.31, width: 0.09, gain: 8.5)
                    + localBoost(t, center: 0.81, width: 0.07, gain: 7.5)
            }
            return min(max(raw, 15), 70)
        }
        return .fromSamples(label: label, samples: values)
    }

    private static func localBoost(_ t: Double, center: Double, width: Double, gain: Double) -> Double {
        let z = (t - center) / width
        return gain * exp(-0.5 * z * z)
    }
}

#Preview("Half Violin Runs") {
    HalfViolinRunSpeedChart(
        runs: MockRunSpeedGenerator.generateFiveRuns(),
        unitLabel: "km/h"
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
