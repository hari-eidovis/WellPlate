import SwiftUI
import SwiftData

struct FastingScheduleEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fastingService: FastingService

    var existingSchedule: FastingSchedule?

    // Active session reference for mid-fast schedule change handling
    var activeSession: FastingSession?

    @State private var selectedType: FastingScheduleType = .ratio16_8
    @State private var eatWindowStart: Date = FastingScheduleEditor.defaultTime(hour: 12, minute: 0)
    @State private var eatWindowEnd: Date = FastingScheduleEditor.defaultTime(hour: 20, minute: 0)
    @State private var caffeineCutoffEnabled: Bool = false
    @State private var cutoffHours: Int = 2
    @State private var showMidFastAlert = false

    var body: some View {
        NavigationStack {
            Form {
                scheduleSection
                eatWindowSection
                caffeineCutoffSection
                infoSection
            }
            .navigationTitle(existingSchedule == nil ? "Fasting Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.r(.body, .medium))
                        .foregroundColor(AppColors.brand)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { handleSave() }
                        .font(.r(.body, .semibold))
                        .foregroundColor(AppColors.brand)
                }
            }
            .alert("Active Fast", isPresented: $showMidFastAlert) {
                Button("End Fast", role: .destructive) { endFastAndSave() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have an active fast. End it and apply the new schedule?")
            }
        }
        .presentationDetents([.large])
        .onAppear { loadExisting() }
    }

    // MARK: - Sections

    private var scheduleSection: some View {
        Section {
            ForEach(FastingScheduleType.allCases) { type in
                Button {
                    HapticService.selectionChanged()
                    selectedType = type
                    applyDefaults(for: type)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: type.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedType == type ? AppColors.brand : .secondary)
                            .frame(width: 28)
                        Text(type.label)
                            .font(.r(.body, .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedType == type {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Schedule")
        }
    }

    private var eatWindowSection: some View {
        Section {
            DatePicker("Starts at", selection: $eatWindowStart, displayedComponents: .hourAndMinute)
                .font(.r(.body, .regular))
                .onChange(of: eatWindowStart) { _ in syncEndFromStart() }

            DatePicker("Ends at", selection: $eatWindowEnd, displayedComponents: .hourAndMinute)
                .font(.r(.body, .regular))
                .onChange(of: eatWindowEnd) { _ in syncTypeFromWindow() }

            HStack {
                Text("Fast duration")
                    .font(.r(.body, .regular))
                    .foregroundColor(.secondary)
                Spacer()
                Text(fastDurationLabel)
                    .font(.r(.body, .semibold))
                    .foregroundColor(AppColors.brand)
            }
        } header: {
            Text("Eat Window")
        }
    }

    private var caffeineCutoffSection: some View {
        Section {
            Toggle("Caffeine cutoff reminder", isOn: $caffeineCutoffEnabled)
                .font(.r(.body, .regular))
            if caffeineCutoffEnabled {
                Stepper("\(cutoffHours)h before eat window ends", value: $cutoffHours, in: 1...4)
                    .font(.r(.body, .regular))
            }
        } header: {
            Text("Caffeine Cutoff")
        }
    }

    private var infoSection: some View {
        Section {
            Text("Your fasting schedule repeats daily. Notifications will remind you when your eating window opens and closes.")
                .font(.r(.caption, .regular))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Computed

    private var fastDurationLabel: String {
        let cal = Calendar.current
        let diff = cal.dateComponents([.hour, .minute], from: eatWindowStart, to: eatWindowEnd)
        var eatHours = diff.hour ?? 0
        let eatMins = diff.minute ?? 0
        if eatHours < 0 { eatHours += 24 }
        let fastHours = 24 - eatHours
        let fastMins = eatMins > 0 ? 60 - eatMins : 0
        let adjustedFastHours = eatMins > 0 ? fastHours - 1 : fastHours
        if fastMins > 0 {
            return "\(adjustedFastHours)h \(fastMins)m"
        }
        return "\(fastHours)h"
    }

    private var eatWindowDurationHours: Double {
        let cal = Calendar.current
        let diff = cal.dateComponents([.hour, .minute], from: eatWindowStart, to: eatWindowEnd)
        var hours = Double(diff.hour ?? 0) + Double(diff.minute ?? 0) / 60.0
        if hours <= 0 { hours += 24 }
        return hours
    }

    // MARK: - Actions

    private func loadExisting() {
        guard let schedule = existingSchedule else { return }
        selectedType = schedule.resolvedScheduleType
        eatWindowStart = Self.defaultTime(hour: schedule.eatWindowStartHour, minute: schedule.eatWindowStartMinute)
        eatWindowEnd = eatWindowStart.addingTimeInterval(schedule.eatWindowDurationHours * 3600)
        caffeineCutoffEnabled = schedule.caffeineCutoffEnabled
        cutoffHours = schedule.caffeineCutoffMinutesBefore / 60
    }

    private func applyDefaults(for type: FastingScheduleType) {
        guard type != .custom else { return }
        eatWindowStart = Self.defaultTime(hour: type.defaultEatStartHour, minute: 0)
        eatWindowEnd = eatWindowStart.addingTimeInterval(type.defaultEatHours * 3600)
    }

    private func syncEndFromStart() {
        if selectedType != .custom {
            eatWindowEnd = eatWindowStart.addingTimeInterval(selectedType.defaultEatHours * 3600)
        }
    }

    private func syncTypeFromWindow() {
        // If user manually changes end, switch to custom
        let hours = eatWindowDurationHours
        let matchingType = FastingScheduleType.allCases.first { $0 != .custom && $0.defaultEatHours == hours }
        selectedType = matchingType ?? .custom
    }

    private func handleSave() {
        if activeSession != nil {
            showMidFastAlert = true
        } else {
            performSave()
        }
    }

    private func endFastAndSave() {
        if let session = activeSession {
            session.completed = false
            session.actualEndAt = .now
        }
        performSave()
    }

    private func performSave() {
        let cal = Calendar.current
        let startComps = cal.dateComponents([.hour, .minute], from: eatWindowStart)
        let startHour = startComps.hour ?? 12
        let startMinute = startComps.minute ?? 0
        let duration = eatWindowDurationHours

        if let schedule = existingSchedule {
            schedule.scheduleType = selectedType.rawValue
            schedule.eatWindowStartHour = startHour
            schedule.eatWindowStartMinute = startMinute
            schedule.eatWindowDurationHours = duration
            schedule.caffeineCutoffEnabled = caffeineCutoffEnabled
            schedule.caffeineCutoffMinutesBefore = cutoffHours * 60
            schedule.isActive = true

            Task {
                await fastingService.requestNotificationPermission()
                fastingService.scheduleNotifications(for: schedule)
            }
        } else {
            let schedule = FastingSchedule(
                scheduleType: selectedType,
                eatWindowStartHour: startHour,
                eatWindowStartMinute: startMinute,
                eatWindowDurationHours: duration,
                isActive: true,
                caffeineCutoffEnabled: caffeineCutoffEnabled,
                caffeineCutoffMinutesBefore: cutoffHours * 60
            )
            modelContext.insert(schedule)

            Task {
                await fastingService.requestNotificationPermission()
                fastingService.scheduleNotifications(for: schedule)
            }

            // First-session creation: if currently in fasting window, create retroactive session
            if fastingService.currentState.isFasting || computeIsFasting(startHour: startHour, startMinute: startMinute, duration: duration) {
                let fastStart = fastingService.mostRecentEatWindowEnd(for: schedule)
                let fastEnd = fastingService.nextEatWindowStart(for: schedule)
                let session = FastingSession(startedAt: fastStart, targetEndAt: fastEnd, scheduleType: selectedType)
                modelContext.insert(session)
            }
        }

        dismiss()
    }

    private func computeIsFasting(startHour: Int, startMinute: Int, duration: Double) -> Bool {
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        let eatStart = cal.date(bySettingHour: startHour, minute: startMinute, second: 0, of: startOfDay) ?? startOfDay
        let eatEnd = eatStart.addingTimeInterval(duration * 3600)
        return now < eatStart || now >= eatEnd
    }

    // MARK: - Helpers

    static func defaultTime(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
