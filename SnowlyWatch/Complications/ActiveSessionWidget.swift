//
//  ActiveSessionWidget.swift
//  SnowlyWatch
//
//  WidgetKit complication for active ski session status.
//

import SwiftUI
import WidgetKit

// MARK: - Entry

struct ActiveSessionEntry: TimelineEntry {
    let date: Date
    let runCount: Int
    let duration: TimeInterval
    let isTracking: Bool
}

// MARK: - Provider

struct ActiveSessionProvider: TimelineProvider {

    func placeholder(in context: Context) -> ActiveSessionEntry {
        ActiveSessionEntry(date: .now, runCount: 3, duration: 3600, isTracking: true)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ActiveSessionEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ActiveSessionEntry>) -> Void
    ) {
        let (isTracking, runCount, duration) = WatchWidgetSharedStore.read()
        let entry = ActiveSessionEntry(
            date: .now,
            runCount: runCount,
            duration: duration,
            isTracking: isTracking
        )
        // Refresh every 5 minutes when tracking; otherwise only on explicit reload.
        let policy: TimelineReloadPolicy = isTracking
            ? .after(.now.addingTimeInterval(300))
            : .never
        completion(Timeline(entries: [entry], policy: policy))
    }
}

// MARK: - Widget

struct ActiveSessionWidget: Widget {

    let kind = SharedConstants.complicationWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveSessionProvider()) { entry in
            ActiveSessionWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringKey("watch_widget_display_name"))
        .description(LocalizedStringKey("watch_widget_description"))
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

// MARK: - Views

struct ActiveSessionWidgetView: View {

    let entry: ActiveSessionEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            circularView
        }
    }

    // MARK: - Circular

    private var circularView: some View {
        VStack(spacing: 2) {
            Image(systemName: "figure.skiing.downhill")
                .font(.title3)
            if entry.isTracking {
                Text("\(entry.runCount)")
                    .font(.caption.bold())
            }
        }
        .widgetAccentable()
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "figure.skiing.downhill")
                Text(LocalizedStringKey("watch_widget_app_name"))
                    .font(.caption.bold())
            }
            .widgetAccentable()

            if entry.isTracking {
                Text(String(format: String(localized: "watch_widget_run_count_format"), entry.runCount))
                    .font(.caption2)
                Text(Formatters.duration(entry.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(LocalizedStringKey("watch_widget_ready"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inline

    private var inlineView: some View {
        if entry.isTracking {
            Text(String(
                format: String(localized: "watch_widget_inline_tracking_format"),
                entry.runCount,
                Formatters.duration(entry.duration)
            ))
        } else {
            Text(LocalizedStringKey("watch_widget_inline_ready"))
        }
    }

    // MARK: - Corner

    private var cornerView: some View {
        Image(systemName: "figure.skiing.downhill")
            .font(.title3)
            .widgetAccentable()
    }
}
