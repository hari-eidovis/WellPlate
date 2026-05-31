import SwiftUI

// MARK: - VoiceMealLogView
// Dedicated voice-input screen for logging a meal by speech.
// Auto-starts recording on appear. Partial transcripts feed the view model's
// `liveTranscript`; the view model auto-commits after 2s of silence, or the user
// can tap Save at any time.
//
// Visual language: Claude palette — Pampas background, White surfaces, Cloudy
// secondary, near-black ink. No Crail (the Claude primary) by request.

struct VoiceMealLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: MealLogViewModel
    let selectedDate: Date

    @State private var pulseScale: CGFloat = 1.0
    @State private var sessionStartedAt: Date?
    @State private var lastPartialAt: Date?

    // MARK: Claude palette (inline — view-scoped to avoid touching shared tokens)
    private let cBackground = Color(red: 0.957, green: 0.953, blue: 0.933) // Pampas  #F4F3EE
    private let cSurface    = Color.white                                  // White   #FFFFFF
    private let cMuted      = Color(red: 0.694, green: 0.678, blue: 0.631) // Cloudy  #B1ADA1
    private let cInk        = Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
    private let cDivider    = Color(red: 0.894, green: 0.886, blue: 0.859) // soft Pampas-stroke

    // MARK: - Derived state

    private var trimmedTranscript: String {
        viewModel.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canFinalizeVoiceLog: Bool {
        !trimmedTranscript.isEmpty
    }

    /// 25-second max — mirrors `AppleSpeechTranscriptionService.maxDurationSeconds`.
    private let maxDurationSeconds: Double = 25

    /// Silence debounce — mirrors `MealLogViewModel.silenceAutoCommitSeconds`.
    private let autoSaveAfterSilence: Double = 2.0

    var body: some View {
        ZStack {
            cBackground.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                content(now: context.date)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        .toolbarBackground(cBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Something went wrong", isPresented: $viewModel.showError) {
            Button("Try Again") { restartSession() }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Microphone Access Required", isPresented: $viewModel.showTranscriptionPermissionAlert) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("Cadence needs microphone and speech recognition access. Enable both in Settings → Privacy.")
        }
        .onAppear {
            sessionStartedAt = Date()
            lastPartialAt = nil
            viewModel.startVoiceAutoLog(selectedDate: selectedDate)
        }
        .onDisappear {
            viewModel.cancelVoiceAutoLog()
        }
        .onChange(of: viewModel.liveTranscript) { _, newValue in
            if !newValue.isEmpty {
                lastPartialAt = Date()
            }
        }
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss {
                HapticService.notify(.success)
                SoundService.playConfirmation()
                dismiss()
            }
        }
        .onChange(of: viewModel.isTranscribing) { _, isRecording in
            if isRecording {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseScale = 1.16
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pulseScale = 1.0
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 8)

            Spacer(minLength: 24)

            micSection(now: now)

            Spacer(minLength: 28)

            transcriptSection

            Spacer(minLength: 16)

            statusBar(now: now)

            Spacer(minLength: 12)

            tipCard

            if viewModel.isLoading {
                loadingPill
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Color.clear.frame(height: 16)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Header

    private var headerSection: some View {
        Text("Speak your meal")
            .font(.system(size: 26, weight: .semibold, design: .serif))
            .foregroundColor(cInk)
            .tracking(-0.4)
    }

    // MARK: - Mic

    private func micSection(now: Date) -> some View {
        let progress = autoSaveProgress(now: now)
        let isCountingDown = canFinalizeVoiceLog && viewModel.isTranscribing && progress > 0

        return ZStack {
            // Outer ambient pulse
            Circle()
                .fill(cSurface.opacity(0.85))
                .frame(width: 188, height: 188)
                .scaleEffect(viewModel.isTranscribing ? pulseScale : 1.0)
                .shadow(color: cMuted.opacity(0.18), radius: 24, x: 0, y: 6)

            // Auto-save countdown arc — sweeps the last 2 seconds of silence.
            // Hidden when not counting down so the idle/listening state stays minimal.
            if isCountingDown {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(cInk.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 152, height: 152)
                    .animation(.linear(duration: 0.1), value: progress)
            }

            // Mic surface
            Circle()
                .fill(cSurface)
                .frame(width: 116, height: 116)
                .overlay(
                    Circle().stroke(cDivider, lineWidth: 1)
                )

            micIcon
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var micIcon: some View {
        if #available(iOS 17, *) {
            Image(systemName: "mic.fill")
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(cInk)
                .symbolEffect(.variableColor.iterative, isActive: viewModel.isTranscribing)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(cInk)
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptSection: some View {
        let placeholder = canFinalizeVoiceLog ? "" : "e.g. \"Avocado toast, 200 grams\""

        VStack(spacing: 8) {
            if canFinalizeVoiceLog {
                Text("\u{201C}\(trimmedTranscript)\u{201D}")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundColor(cInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .transition(.opacity)
            } else {
                Text(placeholder)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundColor(cMuted)
                    .italic()
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.2), value: canFinalizeVoiceLog)
        .animation(.easeInOut(duration: 0.2), value: trimmedTranscript)
    }

    // MARK: - Status bar

    private func statusBar(now: Date) -> some View {
        HStack(spacing: 10) {
            statusDot
            Text(statusLabel(now: now))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(cInk.opacity(0.78))
                .monospacedDigit()

            Spacer()

            Text(durationLabel(now: now))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(cMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cDivider, lineWidth: 1)
                )
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(viewModel.isTranscribing ? cInk : cMuted)
            .frame(width: 7, height: 7)
            .opacity(viewModel.isTranscribing ? (pulseScale > 1.05 ? 1.0 : 0.55) : 0.6)
            .animation(.easeInOut(duration: 0.5), value: pulseScale)
    }

    private func statusLabel(now: Date) -> String {
        if viewModel.isLoading { return "Saving meal…" }
        if !viewModel.isTranscribing { return "Stopped" }

        let progress = autoSaveProgress(now: now)
        if canFinalizeVoiceLog && progress > 0 {
            let remaining = max(0, autoSaveAfterSilence * (1 - progress))
            return String(format: "Auto-saving in %.1fs…", remaining)
        }
        return canFinalizeVoiceLog ? "Listening" : "Listening…"
    }

    private func durationLabel(now: Date) -> String {
        guard let start = sessionStartedAt else { return "0:00 / 0:25" }
        let elapsed = max(0, min(maxDurationSeconds, now.timeIntervalSince(start)))
        return String(format: "%d:%02d / 0:%02d",
                      Int(elapsed) / 60,
                      Int(elapsed) % 60,
                      Int(maxDurationSeconds))
    }

    // MARK: - Tip card

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(cMuted)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hands-free saving")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(cInk)
                Text("Pause for 2 seconds and Cadence will log your meal. Or tap Save to commit now.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(cMuted)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cDivider, lineWidth: 1)
                )
        )
    }

    private var loadingPill: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: cInk))
            Text("Logging your meal…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(cInk.opacity(0.8))
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cDivider, lineWidth: 1)
                )
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Voice Log")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(cInk)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                HapticService.impact(.medium)
                viewModel.commitVoiceAutoLog(selectedDate: selectedDate)
            } label: {
                Text("Save")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(canFinalizeVoiceLog && !viewModel.isLoading ? cInk : cMuted)
            }
            .disabled(!canFinalizeVoiceLog || viewModel.isLoading)
        }
    }

    // MARK: - Auto-save progress

    /// 0...1 representing how close we are to firing the silence-debounce auto-save.
    /// Returns 0 when no partial has arrived yet or when not transcribing.
    private func autoSaveProgress(now: Date) -> Double {
        guard viewModel.isTranscribing,
              let last = lastPartialAt else { return 0 }
        let elapsed = now.timeIntervalSince(last)
        return min(1.0, max(0, elapsed / autoSaveAfterSilence))
    }

    // MARK: - Helpers

    private func restartSession() {
        sessionStartedAt = Date()
        lastPartialAt = nil
        viewModel.startVoiceAutoLog(selectedDate: selectedDate)
    }
}
