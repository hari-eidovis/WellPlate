import SwiftUI
import SwiftData

/// Modal wrapper around `MoodCheckInCard`. Presented from `EngagementGapsCard`
/// and from the top-N driver card when the user taps the Mood factor.
/// Saves to today's `WellnessDayLog.moodRaw` on selection and dismisses.
struct MoodCheckInSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Fires after the mood is persisted, before dismissal. Lets parents
    /// (e.g. StressView) trigger a stress recompute so derived UI like the
    /// "Quick wins" card refreshes immediately.
    var onSaved: (() -> Void)? = nil

    @State private var selectedMood: MoodOption? = nil
    /// Snapshot of the persisted mood at sheet open. Used to ignore the
    /// `onChange` fired by restoring `selectedMood` in `onAppear` so the
    /// sheet doesn't save-and-dismiss the moment it appears.
    @State private var initialMood: MoodOption? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                MoodCheckInCard(selectedMood: $selectedMood) { mood in
                    saveMood(mood)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("How are you feeling?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            let loaded = todaysMood()
            initialMood = loaded
            selectedMood = loaded
        }
        .onChange(of: selectedMood) { newValue in
            // Skip the restore-from-store change; only react to user picks
            // that actually differ from what's already saved.
            guard let mood = newValue, mood != initialMood else { return }
            saveMood(mood)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Persistence

    private func todaysMood() -> MoodOption? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == today }
        )
        guard let raw = (try? modelContext.fetch(descriptor))?.first?.moodRaw else { return nil }
        return MoodOption(rawValue: raw)
    }

    private func saveMood(_ mood: MoodOption) {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == today }
        )
        let log: WellnessDayLog
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            log = existing
        } else {
            log = WellnessDayLog(day: Date())
            modelContext.insert(log)
        }
        log.moodRaw = mood.rawValue
        try? modelContext.save()
        HapticService.impact(.light)
        onSaved?()
        dismiss()
    }
}
