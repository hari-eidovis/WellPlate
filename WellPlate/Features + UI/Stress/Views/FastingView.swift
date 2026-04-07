import SwiftUI
import SwiftData

// MARK: - Sheet Enum

private enum FastingSheet: Identifiable {
    case scheduleEditor

    var id: String {
        switch self {
        case .scheduleEditor: return "scheduleEditor"
        }
    }
}

// MARK: - FastingView

struct FastingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \FastingSchedule.createdAt, order: .reverse) private var schedules: [FastingSchedule]
    @Query(sort: \FastingSession.startedAt, order: .reverse) private var sessions: [FastingSession]
    @Query private var stressReadings: [StressReading]

    @StateObject private var fastingService = FastingService()
    @State private var activeFastingSheet: FastingSheet?
    @State private var showBreakFastAlert = false
    @State private var previousState: FastingState = .notConfigured

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        _stressReadings = Query(
            filter: #Predicate<StressReading> { $0.timestamp >= cutoff },
            sort: \.timestamp,
            order: .forward
        )
    }

    private var schedule: FastingSchedule? { schedules.first }
    private var activeSession: FastingSession? { sessions.first(where: { $0.isActive }) }
    private var completedSessions: [FastingSession] {
        Array(sessions.filter { !$0.isActive }.prefix(7))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    timerCard
                    if schedule != nil {
                        todayInfoCard
                    }
                    if fastingService.notificationsBlocked {
                        notificationHint
                    }
                    FastingInsightChart(sessions: sessions, readings: stressReadings)
                    if !completedSessions.isEmpty {
                        historySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Fasting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.r(.body, .medium))
                        .foregroundColor(AppColors.brand)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticService.impact(.light)
                        activeFastingSheet = .scheduleEditor
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                    }
                }
            }
            .sheet(item: $activeFastingSheet) { sheet in
                switch sheet {
                case .scheduleEditor:
                    FastingScheduleEditor(
                        fastingService: fastingService,
                        existingSchedule: schedule,
                        activeSession: activeSession
                    )
                }
            }
            .alert("End Fast?", isPresented: $showBreakFastAlert) {
                Button("End Fast", role: .destructive) { breakCurrentFast() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will end your current fast early.")
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { configureService() }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            configureService()
        }
        .onChange(of: fastingService.currentState) { newState in
            handleStateTransition(from: previousState, to: newState)
            previousState = newState
        }
    }

    // MARK: - Timer Card

    private var timerCard: some View {
        Group {
            if schedule == nil {
                emptyStateCard
            } else {
                activeTimerCard
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Set up your fasting schedule")
                .font(.r(.headline, .semibold))

            Text("Track intermittent fasting and see how it correlates with your stress score.")
                .font(.r(.footnote, .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                HapticService.impact(.light)
                activeFastingSheet = .scheduleEditor
            } label: {
                Text("Get Started")
                    .font(.r(.body, .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private var activeTimerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)

                // Progress ring
                Circle()
                    .trim(from: 0, to: fastingService.progress)
                    .stroke(
                        ringColor.gradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: fastingService.progress)

                // Center text
                VStack(spacing: 4) {
                    Text(stateLabel)
                        .font(.r(.caption, .semibold))
                        .foregroundColor(ringColor)

                    Text(formattedTimeRemaining)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("remaining")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 180, height: 180)

            if let sched = schedule {
                Text(sched.resolvedScheduleType.label)
                    .font(.r(.footnote, .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Today Info Card

    private var todayInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sched = schedule {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text(eatWindowLabel(for: sched))
                        .font(.r(.footnote, .medium))
                    Spacer()
                }

                if fastingService.isCaffeineCutoffActive {
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Caffeine cutoff active")
                            .font(.r(.caption, .medium))
                            .foregroundColor(.orange)
                    }
                }

                if fastingService.currentState.isFasting {
                    Button {
                        HapticService.impact(.light)
                        showBreakFastAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                            Text("Break Fast")
                                .font(.r(.footnote, .semibold))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Notification Hint

    private var notificationHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            Text("Enable notifications in Settings → WellPlate for fasting reminders.")
                .font(.r(.caption, .regular))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 10, y: 3)
        )
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Fasts")
                .font(.r(.headline, .semibold))

            ForEach(completedSessions, id: \.persistentModelID) { session in
                HStack(spacing: 12) {
                    Image(systemName: session.completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(session.completed ? .green : .red)
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.startedAt, style: .date)
                            .font(.r(.footnote, .medium))
                        Text(formattedDuration(session.actualDurationSeconds))
                            .font(.r(.caption, .regular))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(session.completed ? "Completed" : "Broken")
                        .font(.r(.caption, .medium))
                        .foregroundColor(session.completed ? .green : .red)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - State Management

    private func configureService() {
        if let schedule {
            fastingService.configure(schedule: schedule, activeSession: activeSession)
            previousState = fastingService.currentState
        }
    }

    private func handleStateTransition(from oldState: FastingState, to newState: FastingState) {
        guard let schedule else { return }

        // Eating → Fasting: create new session
        if oldState.isEating && newState.isFasting && activeSession == nil {
            let fastStart = fastingService.mostRecentEatWindowEnd(for: schedule)
            let fastEnd = fastingService.nextEatWindowStart(for: schedule)
            let session = FastingSession(startedAt: fastStart, targetEndAt: fastEnd,
                                         scheduleType: schedule.resolvedScheduleType)
            modelContext.insert(session)
        }

        // Fasting → Eating: complete active session
        if oldState.isFasting && newState.isEating, let session = activeSession {
            session.completed = true
            session.actualEndAt = .now
            HapticService.notify(.success)
        }
    }

    private func breakCurrentFast() {
        guard let session = activeSession else { return }
        session.completed = false
        session.actualEndAt = .now
    }

    // MARK: - Formatting

    private var stateLabel: String {
        switch fastingService.currentState {
        case .fasting: return "FASTING"
        case .eating:  return "EATING"
        case .notConfigured: return ""
        }
    }

    private var ringColor: Color {
        switch fastingService.currentState {
        case .fasting: return .orange
        case .eating:  return .green
        case .notConfigured: return .secondary
        }
    }

    private var formattedTimeRemaining: String {
        formattedDuration(fastingService.timeRemaining)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        let s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }

    private func eatWindowLabel(for schedule: FastingSchedule) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let cal = Calendar.current
        let start = cal.date(bySettingHour: schedule.eatWindowStartHour,
                             minute: schedule.eatWindowStartMinute,
                             second: 0, of: Date()) ?? Date()
        let end = start.addingTimeInterval(schedule.eatWindowDurationHours * 3600)
        return "Eat: \(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}
