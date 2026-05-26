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
    @State private var lastLiveActivityProgress: Double = -1
    @State private var celebration: FastingCompletionEvent?

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
            .background(backgroundCanvas)
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
            .alert("Break Fast Early?", isPresented: $showBreakFastAlert) {
                Button("Break Fast", role: .destructive) { breakCurrentFast() }
                Button("Keep Going", role: .cancel) { }
            } message: {
                Text(breakFastAlertMessage)
            }
        }
        .presentationDragIndicator(.visible)
        .overlay {
            if let celebration {
                FastingCelebrationOverlay(event: celebration) {
                    self.celebration = nil
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onAppear { configureService() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            configureService()
        }
        .onChange(of: fastingService.currentState) { _, newState in
            handleStateTransition(from: previousState, to: newState)
            previousState = newState
        }
        .onChange(of: fastingService.progress) { _, newProgress in
            syncLiveActivityProgress(newProgress)
        }
    }

    /// Friendly elapsed-time string for the break-fast confirmation alert.
    private var breakFastAlertMessage: String {
        guard let session = activeSession else {
            return "Are you sure you want to end your fast?"
        }
        let elapsed = Date().timeIntervalSince(session.startedAt)
        return "You've fasted for \(formattedDuration(elapsed)). Ending now means this won't count as a completed fast."
    }

    // MARK: - Background

    private var backgroundCanvas: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()
            LinearGradient(
                colors: [heroAccent.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 360)
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
    }

    private var heroAccent: Color {
        switch fastingService.currentState {
        case .fasting: return Color(hue: 0.07, saturation: 0.78, brightness: 0.95)
        case .eating:  return Color(hue: 0.40, saturation: 0.62, brightness: 0.72)
        case .notConfigured: return AppColors.brand
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
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.brand.opacity(0.22), AppColors.brand.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(AppColors.brand)
            }

            VStack(spacing: 8) {
                Text("Set Up Fasting")
                    .font(.r(20, .bold))
                    .foregroundStyle(.primary)
                Text("Track intermittent fasting and see how it correlates with your stress score.")
                    .font(.r(13, .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                HapticService.impact(.light)
                activeFastingSheet = .scheduleEditor
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Get Started")
                        .font(.r(15, .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.brand, AppColors.brand.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: AppColors.brand.opacity(0.35), radius: 10, x: 0, y: 4)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 16, y: 6)
        )
    }

    /// True when the schedule says we should be fasting but there's no active
    /// session — typically after the user broke a fast early, or the schedule
    /// was just configured during a fasting window.
    private var isIdleInFastingWindow: Bool {
        fastingService.currentState.isFasting && activeSession == nil
    }

    private var activeTimerCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                Circle()
                    .fill(heroAccent)
                    .frame(width: 7, height: 7)
                Text(idleHeaderLabel)
                    .font(.r(11, .bold))
                    .tracking(1.4)
                    .foregroundStyle(heroAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(heroAccent.opacity(0.14)))

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [heroAccent.opacity(0.14), .clear],
                            center: .center,
                            startRadius: 5,
                            endRadius: 120
                        )
                    )
                    .frame(width: 230, height: 230)
                    .blur(radius: 4)

                Circle()
                    .stroke(heroAccent.opacity(0.14), lineWidth: 14)
                    .frame(width: 200, height: 200)

                if !isIdleInFastingWindow {
                    Circle()
                        .trim(from: 0, to: max(fastingService.progress, 0.001))
                        .stroke(
                            LinearGradient(
                                colors: [heroAccent, heroAccent.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 200, height: 200)
                        .animation(.linear(duration: 0.3), value: fastingService.progress)
                }

                VStack(spacing: 4) {
                    if isIdleInFastingWindow {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(heroAccent.opacity(0.85))
                        Text("READY WHEN YOU ARE")
                            .font(.r(10, .bold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(formattedTimeRemaining)
                            .font(.r(38, .heavy))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text("REMAINING")
                            .font(.r(10, .bold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                        if fastingService.progress > 0 {
                            Text("\(Int(fastingService.progress * 100))% complete")
                                .font(.r(12, .semibold))
                                .foregroundStyle(heroAccent)
                                .padding(.top, 2)
                        }
                    }
                }
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: isIdleInFastingWindow)

            if let sched = schedule {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(sched.displayLabel)
                        .font(.r(12, .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [heroAccent.opacity(0.10), heroAccent.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(heroAccent.opacity(0.16), lineWidth: 1)
                )
                .appShadow(radius: 18, y: 7)
        )
    }

    // MARK: - Today Info Card

    private var todayInfoCard: some View {
        let eatColor = Color(hue: 0.40, saturation: 0.62, brightness: 0.72)
        return VStack(alignment: .leading, spacing: 12) {
            if let sched = schedule {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [eatColor.opacity(0.22), eatColor.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 34, height: 34)
                        Image(systemName: "clock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(eatColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EAT WINDOW")
                            .font(.r(10, .bold))
                            .tracking(0.7)
                            .foregroundStyle(eatColor.opacity(0.85))
                        Text(eatWindowDisplay(for: sched))
                            .font(.r(14, .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemFill).opacity(0.55))
                )

                if fastingService.isCaffeineCutoffActive {
                    HStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("Caffeine cutoff active")
                            .font(.r(13, .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                            )
                    )
                }

                if fastingService.currentState.isFasting && activeSession != nil {
                    Button {
                        HapticService.impact(.light)
                        showBreakFastAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Break Fast")
                                .font(.r(14, .bold))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                } else if fastingService.currentState.isFasting && activeSession == nil {
                    Button {
                        HapticService.impact(.medium)
                        startFastNow()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Start Fast Now")
                                .font(.r(14, .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [heroAccent, heroAccent.opacity(0.78)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: heroAccent.opacity(0.35), radius: 10, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 14, y: 5)
        )
    }

    // MARK: - Notification Hint

    private var notificationHint: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Text("Enable notifications in Settings → Cadence for fasting reminders.")
                .font(.r(12, .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.brand.opacity(0.22), AppColors.brand.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("HISTORY")
                        .font(.r(10, .bold))
                        .tracking(0.7)
                        .foregroundStyle(AppColors.brand.opacity(0.85))
                    Text("Recent Fasts")
                        .font(.r(16, .bold))
                        .foregroundStyle(.primary)
                }
            }

            VStack(spacing: 8) {
                ForEach(completedSessions, id: \.persistentModelID) { session in
                    fastHistoryRow(session)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 14, y: 5)
        )
    }

    private func fastHistoryRow(_ session: FastingSession) -> some View {
        let result: Color = session.completed ? Color(hue: 0.40, saturation: 0.62, brightness: 0.72) : .red
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(result.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: session.completed ? "checkmark" : "xmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(result)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt, style: .date)
                    .font(.r(13, .semibold))
                    .foregroundStyle(.primary)
                Text(formattedDuration(session.actualDurationSeconds))
                    .font(.r(11, .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(session.completed ? "Completed" : "Broken")
                .font(.r(11, .bold))
                .foregroundStyle(result)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(result.opacity(0.14)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.55))
        )
    }

    // MARK: - State Management

    private func configureService() {
        if let schedule {
            fastingService.configure(schedule: schedule, activeSession: activeSession)
            previousState = fastingService.currentState

            // If fasting and no Live Activity running, start one (e.g. after app relaunch or first F7 use)
            if fastingService.currentState.isFasting && !ActivityManager.shared.isFastingActivityActive {
                if let session = activeSession {
                    lastLiveActivityProgress = -1
                    ActivityManager.shared.startFastingActivity(
                        scheduleLabel: schedule.displayLabel,
                        fastStartDate: session.startedAt,
                        targetEndDate: session.targetEndAt
                    )
                    syncLiveActivityProgress(fastingService.progress)
                }
            }
        }
    }

    private func handleStateTransition(from oldState: FastingState, to newState: FastingState) {
        guard let schedule else { return }

        // Eating → Fasting: create new session + start Live Activity
        if oldState.isEating && newState.isFasting && activeSession == nil {
            let fastStart = fastingService.mostRecentEatWindowEnd(for: schedule)
            let fastEnd = fastingService.nextEatWindowStart(for: schedule)
            let session = FastingSession(startedAt: fastStart, targetEndAt: fastEnd,
                                         scheduleType: schedule.resolvedScheduleType)
            modelContext.insert(session)

            lastLiveActivityProgress = -1
            ActivityManager.shared.startFastingActivity(
                scheduleLabel: schedule.displayLabel,
                fastStartDate: fastStart,
                targetEndDate: fastEnd
            )
        }

        // Fasting → Eating: complete active session + end Live Activity + celebrate
        if oldState.isFasting && newState.isEating, let session = activeSession {
            let elapsedHours = session.actualDurationHours
            session.completed = true
            session.actualEndAt = .now
            HapticService.notify(.success)
            ActivityManager.shared.endFastingActivity(completed: true)
            withAnimation(.easeOut(duration: 0.3)) {
                celebration = FastingCompletionEvent(
                    durationHours: elapsedHours,
                    scheduleLabel: schedule.displayLabel
                )
            }
        }
    }

    /// Manually starts a fast right now — used when the schedule says we
    /// should be fasting but no active session exists (e.g. after the user
    /// broke the previous fast early).
    private func startFastNow() {
        guard let schedule else { return }
        let now = Date()
        let targetEnd = fastingService.nextEatWindowStart(for: schedule)
        let session = FastingSession(startedAt: now, targetEndAt: targetEnd,
                                     scheduleType: schedule.resolvedScheduleType)
        modelContext.insert(session)
        try? modelContext.save()

        lastLiveActivityProgress = -1
        ActivityManager.shared.startFastingActivity(
            scheduleLabel: schedule.displayLabel,
            fastStartDate: now,
            targetEndDate: targetEnd
        )

        // Recompute service state immediately so the timer card reflects the
        // new session instead of waiting for the next 1s tick.
        fastingService.configure(schedule: schedule, activeSession: session)
        previousState = fastingService.currentState
        syncLiveActivityProgress(fastingService.progress)
    }

    /// Pushes the current progress to the running Live Activity, throttled to
    /// changes of ≥0.5% so the system rate limiter is happy.
    private func syncLiveActivityProgress(_ progress: Double) {
        guard ActivityManager.shared.isFastingActivityActive else { return }
        if lastLiveActivityProgress < 0 || abs(progress - lastLiveActivityProgress) >= 0.005 {
            lastLiveActivityProgress = progress
            ActivityManager.shared.updateFastingActivity(progress: progress)
        }
    }

    private func breakCurrentFast() {
        guard let session = activeSession else { return }
        session.completed = false
        session.actualEndAt = .now
        ActivityManager.shared.endFastingActivity(completed: false)
        lastLiveActivityProgress = -1
    }

    // MARK: - Formatting

    private var stateLabel: String {
        switch fastingService.currentState {
        case .fasting: return "FASTING"
        case .eating:  return "EATING"
        case .notConfigured: return ""
        }
    }

    /// State pill copy at the top of the timer card. Shows "READY" when the
    /// schedule says we should be fasting but no session is running yet.
    private var idleHeaderLabel: String {
        isIdleInFastingWindow ? "READY TO FAST" : stateLabel
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

    private func eatWindowDisplay(for schedule: FastingSchedule) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let cal = Calendar.current
        let start = cal.date(bySettingHour: schedule.eatWindowStartHour,
                             minute: schedule.eatWindowStartMinute,
                             second: 0, of: Date()) ?? Date()
        let end = start.addingTimeInterval(schedule.eatWindowDurationHours * 3600)
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}
