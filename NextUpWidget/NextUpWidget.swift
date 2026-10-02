import WidgetKit
import SwiftUI
import SwiftData

// Widget target only. Replaces the template's NextUpWidget.swift.

struct NextUpEntry: TimelineEntry {
    let date: Date
    let upcoming: [Occurrence]
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(date: .now, upcoming: [.sample])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let entry = makeEntry()
        let halfHour = Date().addingTimeInterval(1800)
        let refresh = entry.upcoming.first.map { min($0.end, halfHour) } ?? halfHour
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> NextUpEntry {
        let modelContext = ModelContext(SharedStore.container)
        let activities = (try? modelContext.fetch(FetchDescriptor<Activity>())) ?? []
        let now = Date()
        let occ = Planner.occurrences(activities, from: now, to: now.addingTimeInterval(3 * 86_400))
        return NextUpEntry(date: now, upcoming: Array(occ.prefix(3)))
    }
}

struct NextUpWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextUpEntry

    var body: some View {
        if let next = entry.upcoming.first {
            switch family {
            case .accessoryInline:
                Text("\(next.activityName) \(next.start, style: .time)")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(next.activityName).font(.headline)
                    Text("\(next.start, format: .dateTime.weekday(.abbreviated).hour().minute())")
                    if let leave = next.leaveBy {
                        Text("Leave \(leave, style: .time)")
                    }
                }
            case .systemMedium:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next up").font(.caption).foregroundStyle(.secondary)
                    ForEach(entry.upcoming) { o in
                        HStack {
                            Circle().fill(Color(hex: o.colorHex)).frame(width: 8, height: 8)
                            Text(o.activityName).font(.subheadline.bold()).lineLimit(1)
                            Spacer()
                            Text(o.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(Color(hex: next.colorHex)).frame(width: 8, height: 8)
                        Text("Next up").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(next.activityName).font(.headline).lineLimit(2)
                    Text(next.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.subheadline)
                    if let leave = next.leaveBy {
                        Label {
                            Text(leave, style: .time)
                        } icon: {
                            Image(systemName: "car.fill")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            Text("Nothing scheduled").font(.caption)
        }
    }
}

struct NextUpWidget: Widget {
    let kind = "NextUpWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextUpProvider()) { entry in
            NextUpWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Up")
        .description("Next family activity and leave-by time.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
