import SwiftUI
import SwiftData

// MARK: - SymptomHistoryView

struct SymptomHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SymptomEntry.timestamp, order: .reverse) private var entries: [SymptomEntry]

    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .navigationTitle("Symptom History")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("No symptoms logged yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Log a symptom from the Home screen\nor the Profile tab to start tracking.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(groupedEntries, id: \.key) { group in
                Section {
                    ForEach(group.entries) { entry in
                        entryRow(entry)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete { offsets in
                        deleteEntries(from: group.entries, at: offsets)
                    }
                } header: {
                    Text(group.key)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func entryRow(_ entry: SymptomEntry) -> some View {
        let isExpanded = expandedIDs.contains(entry.id)
        let cat = entry.resolvedCategory

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Category icon
                Image(systemName: cat?.icon ?? "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(cat?.color ?? .secondary)
                    .frame(width: 20)

                // Name + category pill
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    if let cat {
                        Text(cat.label)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(cat.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(cat.color.opacity(0.12)))
                    }
                }

                Spacer()

                // Severity badge
                severityBadge(entry.severity)

                // Time
                Text(timeString(for: entry.timestamp))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Notes (expandable)
            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded { expandedIDs.remove(entry.id) }
                            else { expandedIDs.insert(entry.id) }
                        }
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .accessibilityLabel("\(entry.name), severity \(entry.severity) out of 10")
    }

    private func severityBadge(_ severity: Int) -> some View {
        let color: Color = {
            switch severity {
            case 1...3: return Color(hue: 0.38, saturation: 0.58, brightness: 0.72)
            case 4...6: return Color(hue: 0.14, saturation: 0.72, brightness: 0.95)
            default:    return Color(hue: 0.00, saturation: 0.72, brightness: 0.85)
            }
        }()

        return Text("\(severity)/10")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Grouping

    private struct EntryGroup {
        let key: String
        let entries: [SymptomEntry]
    }

    private var groupedEntries: [EntryGroup] {
        let cal = Calendar.current
        var groups: [EntryGroup] = []
        var seen: Set<String> = []

        for entry in entries {
            let key: String
            if cal.isDateInToday(entry.day)      { key = "Today" }
            else if cal.isDateInYesterday(entry.day) { key = "Yesterday" }
            else {
                let f = DateFormatter(); f.dateFormat = "MMMM d, yyyy"
                key = f.string(from: entry.day)
            }
            if !seen.contains(key) {
                seen.insert(key)
                groups.append(EntryGroup(key: key, entries: []))
            }
            if let idx = groups.firstIndex(where: { $0.key == key }) {
                groups[idx] = EntryGroup(key: key, entries: groups[idx].entries + [entry])
            }
        }
        return groups
    }

    private func timeString(for date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }

    private func deleteEntries(from entries: [SymptomEntry], at offsets: IndexSet) {
        for i in offsets { modelContext.delete(entries[i]) }
        try? modelContext.save()
    }
}

// MARK: - Preview

#Preview("Symptom History") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SymptomEntry.self, configurations: config)
    let ctx = container.mainContext
    let samples: [(String, SymptomCategory, Int)] = [
        ("Headache", .pain, 6), ("Bloating", .digestive, 4), ("Fatigue", .energy, 7)
    ]
    for (name, cat, sev) in samples {
        ctx.insert(SymptomEntry(name: name, category: cat, severity: sev))
    }
    return NavigationStack { SymptomHistoryView() }.modelContainer(container)
}

#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SymptomEntry.self, configurations: config)
    return NavigationStack { SymptomHistoryView() }.modelContainer(container)
}
