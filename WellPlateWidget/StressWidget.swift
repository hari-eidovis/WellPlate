import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct StressEntry: TimelineEntry {
    let date: Date
    let data: WidgetStressData
}

// MARK: - Timeline Provider

struct StressWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> StressEntry {
        StressEntry(date: .now, data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StressEntry) -> Void) {
        let data = context.isPreview ? .placeholder : WidgetStressData.load()
        completion(StressEntry(date: .now, data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StressEntry>) -> Void) {
        let entry     = StressEntry(date: .now, data: WidgetStressData.load())
        let nextFetch = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline  = Timeline(entries: [entry], policy: .after(nextFetch))
        completion(timeline)
    }
}

// MARK: - Widget Entry View

struct StressWidgetEntryView: View {
    let entry: StressEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            StressSmallView(data: entry.data)
        case .systemMedium:
            StressMediumView(data: entry.data)
        case .systemLarge:
            StressLargeView(data: entry.data)
        default:
            StressSmallView(data: entry.data)
        }
    }
}

// MARK: - Widget Declaration

struct StressWidget: Widget {
    let kind = "com.hariom.wellplate.stressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StressWidgetProvider()) { entry in
            StressWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Stress Level")
        .description("Monitor your stress score and top factors.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#if DEBUG
struct StressWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StressWidgetEntryView(entry: StressEntry(date: .now, data: .placeholder))
                .previewContext(WidgetPreviewContext(family: .systemSmall))

            StressWidgetEntryView(entry: StressEntry(date: .now, data: .placeholder))
                .previewContext(WidgetPreviewContext(family: .systemMedium))

            StressWidgetEntryView(entry: StressEntry(date: .now, data: .placeholder))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
