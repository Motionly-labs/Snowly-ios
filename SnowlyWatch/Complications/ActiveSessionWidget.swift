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
        let entry = ActiveSessionEntry(
            date: .now,
            runCount: 0,
            duration: 0,
            isTracking: false
        )
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Widget

struct ActiveSessionWidget: Widget {

    let kind = "ActiveSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveSessionProvider()) { entry in
            ActiveSessionWidgetView(entry: entry)
        }
        .configurationDisplayName("watch_widget_display_name")
        .description("watch_widget_description")
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
                Text("watch_widget_app_name")
                    .font(.caption.bold())
            }
            .widgetAccentable()

            if entry.isTracking {
                Text("watch_widget_run_count_format \(entry.runCount)")
                    .font(.caption2)
                Text(Formatters.duration(entry.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("watch_widget_ready")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inline

    private var inlineView: some View {
        if entry.isTracking {
            Text("watch_widget_inline_tracking_format \(entry.runCount) \(Formatters.duration(entry.duration))")
        } else {
            Text("watch_widget_inline_ready")
        }
    }

    // MARK: - Corner

    private var cornerView: some View {
        Image(systemName: "figure.skiing.downhill")
            .font(.title3)
            .widgetAccentable()
    }
}
