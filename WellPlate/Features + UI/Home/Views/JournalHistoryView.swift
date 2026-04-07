import SwiftUI
import SwiftData

// MARK: - JournalHistoryView
//
// Chronological list of past journal entries.
// Presented as a navigationDestination from HomeView.

struct JournalHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]

    @State private var expandedEntryIDs: Set<PersistentIdentifier> = []

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                entriesList
            }
        }
        .navigationTitle("Journal History")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(.tertiaryLabel))

            Text("No journal entries yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Start your first journal entry\nfrom the Home screen after logging your mood.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entries List

    private var entriesList: some View {
        List {
            ForEach(groupedEntries, id: \.key) { group in
                Section(header:
                    Text(group.key)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                ) {
                    ForEach(group.entries) { entry in
                        entryCard(entry)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        deleteEntries(from: group.entries, at: offsets)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Entry Card

    private func entryCard(_ entry: JournalEntry) -> some View {
        let isExpanded = expandedEntryIDs.contains(entry.persistentModelID)

        return VStack(alignment: .leading, spacing: 10) {
            // Mood + timestamp row
            HStack {
                if let mood = entry.mood {
                    HStack(spacing: 4) {
                        Text(mood.emoji)
                            .font(.system(size: 15))
                        Text(mood.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(mood.accentColor)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(mood.accentColor.opacity(0.12)))
                }

                Spacer()

                Text(timeString(for: entry.createdAt))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Entry text
            Text(entry.text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 3)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

            // Expand/collapse if text is long
            if entry.text.count > 120 {
                Button {
                    if isExpanded {
                        expandedEntryIDs.remove(entry.persistentModelID)
                    } else {
                        expandedEntryIDs.insert(entry.persistentModelID)
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "Show more")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.brand)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .accessibilityLabel(accessibilityLabel(for: entry))
        .accessibilityHint("Double-tap to expand or collapse")
    }

    // MARK: - Grouped Entries

    private struct EntryGroup: Identifiable {
        let key: String
        let entries: [JournalEntry]
        var id: String { key }
    }

    private var groupedEntries: [EntryGroup] {
        let calendar = Calendar.current
        var groups: [EntryGroup] = []
        var seen: Set<String> = []

        for entry in entries {
            let key: String
            if calendar.isDateInToday(entry.day) {
                key = "Today"
            } else if calendar.isDateInYesterday(entry.day) {
                key = "Yesterday"
            } else {
                let f = DateFormatter()
                f.dateFormat = "MMMM d, yyyy"
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

    // MARK: - Helpers

    private func timeString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private func accessibilityLabel(for entry: JournalEntry) -> String {
        let moodPart = entry.mood.map { "\($0.label) mood. " } ?? ""
        let preview = String(entry.text.prefix(80))
        return "\(moodPart)\(preview)"
    }

    private func deleteEntries(from entries: [JournalEntry], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        do {
            try modelContext.save()
        } catch {
            WPLogger.home.error("Journal delete failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview("Journal History") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: JournalEntry.self, configurations: config)

    let context = container.mainContext
    let entries: [(String, MoodOption, Int)] = [
        ("I'm grateful for the quiet morning coffee before everything started.", .good, -0),
        ("Work was stressful but I managed to take a walk at lunch. That helped.", .okay, -1),
        ("Feeling great today. Got a lot done and had a good conversation.", .great, -3),
    ]
    for (text, mood, daysAgo) in entries {
        let date = Calendar.current.date(byAdding: .day, value: daysAgo, to: Date()) ?? Date()
        let entry = JournalEntry(day: date, text: text, moodRaw: mood.rawValue)
        context.insert(entry)
    }

    return NavigationStack {
        JournalHistoryView()
    }
    .modelContainer(container)
}

#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: JournalEntry.self, configurations: config)
    return NavigationStack {
        JournalHistoryView()
    }
    .modelContainer(container)
}
