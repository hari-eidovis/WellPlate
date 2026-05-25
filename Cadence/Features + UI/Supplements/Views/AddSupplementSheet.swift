import SwiftUI
import SwiftData

struct AddSupplementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var editingSupplement: SupplementEntry?
    @ObservedObject var service: SupplementService

    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var selectedCategory: SupplementCategory = .vitamin
    @State private var scheduledTimes: [Date] = [defaultTime()]
    @State private var activeDays: Set<Int> = []         // Empty = every day
    @State private var notificationsEnabled: Bool = true
    @State private var notes: String = ""

    private var isEditing: Bool { editingSupplement != nil }

    private static func defaultTime() -> Date {
        var comps = DateComponents()
        comps.hour = 8; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    nameSection
                    dosageSection
                    categorySection
                    timesSection
                    daysSection
                    notificationToggle
                    notesSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Supplement" : "Add Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveSupplement() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.brand.opacity(0.4) : AppColors.brand)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { populateFromEditing() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            TextField("e.g. Magnesium, Vitamin D3...", text: $name)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
    }

    private var dosageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dosage")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            TextField("e.g. 400mg, 5000 IU...", text: $dosage)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SupplementCategory.allCases) { cat in
                        Button {
                            HapticService.impact(.light)
                            selectedCategory = cat
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 13, weight: .medium))
                                Text(cat.label)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(selectedCategory == cat ? .white : cat.color)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                Capsule().fill(selectedCategory == cat ? cat.color : cat.color.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var timesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reminder Times")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(scheduledTimes.indices, id: \.self) { index in
                HStack {
                    DatePicker("", selection: $scheduledTimes[index], displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(AppColors.brand)
                    if scheduledTimes.count > 1 {
                        Button {
                            scheduledTimes.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                }
            }
            Button {
                HapticService.impact(.light)
                scheduledTimes.append(Self.defaultTime())
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                    Text("Add time")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundStyle(AppColors.brand)
            }
        }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Active Days")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if activeDays.isEmpty {
                    Text("Every day")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.brand)
                }
            }
            let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { day in
                    let isOn = activeDays.contains(day)
                    Button {
                        HapticService.impact(.light)
                        if isOn { activeDays.remove(day) } else { activeDays.insert(day) }
                    } label: {
                        Text(dayLabels[day])
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(isOn ? .white : .secondary)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle().fill(isOn ? AppColors.brand : Color(.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notificationToggle: some View {
        Toggle(isOn: $notificationsEnabled) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.brand)
                Text("Enable notifications")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }
        }
        .tint(AppColors.brand)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (optional)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            TextField("e.g. Take with food...", text: $notes, axis: .vertical)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .lineLimit(2...4)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
    }

    // MARK: - Save

    private func saveSupplement() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let timeMinutes = scheduledTimes.map { date -> Int in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 8) * 60 + (comps.minute ?? 0)
        }.sorted()

        let daysArray = activeDays.sorted()

        if let existing = editingSupplement {
            existing.name = trimmedName
            existing.dosage = dosage
            existing.category = selectedCategory.rawValue
            existing.scheduledTimes = timeMinutes
            existing.activeDays = daysArray
            existing.notificationsEnabled = notificationsEnabled
            existing.notes = notes.isEmpty ? nil : notes
        } else {
            let entry = SupplementEntry(
                name: trimmedName,
                dosage: dosage,
                category: selectedCategory,
                scheduledTimes: timeMinutes,
                activeDays: daysArray,
                notificationsEnabled: notificationsEnabled,
                notes: notes.isEmpty ? nil : notes
            )
            modelContext.insert(entry)
        }

        do {
            try modelContext.save()
            let saved = editingSupplement ?? SupplementEntry(name: trimmedName) // for notification scheduling
            if notificationsEnabled {
                Task {
                    await service.requestNotificationPermission()
                    // Re-fetch or use the editing entry for scheduling
                    if let existing = editingSupplement {
                        service.scheduleNotifications(for: existing)
                    }
                }
            }
            HapticService.notify(.success)
            WPLogger.home.info("Supplement saved: \(trimmedName)")
        } catch {
            WPLogger.home.error("Supplement save failed: \(error.localizedDescription)")
        }
        dismiss()
    }

    private func populateFromEditing() {
        guard let s = editingSupplement else { return }
        name = s.name
        dosage = s.dosage
        selectedCategory = s.resolvedCategory ?? .vitamin
        scheduledTimes = s.scheduledTimes.map { minutes in
            var comps = DateComponents()
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            return Calendar.current.date(from: comps) ?? Date()
        }
        activeDays = Set(s.activeDays)
        notificationsEnabled = s.notificationsEnabled
        notes = s.notes ?? ""
    }
}

// MARK: - Preview

#Preview("Add Supplement") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SupplementEntry.self, AdherenceLog.self, configurations: config)
    return AddSupplementSheet(service: SupplementService())
        .modelContainer(container)
}
