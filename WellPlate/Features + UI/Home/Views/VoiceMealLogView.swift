import SwiftUI

// MARK: - VoiceMealLogView
// Dedicated voice-input screen for logging a meal by speech.
// Auto-starts recording on appear. When speech finalises, the ViewModel
// sets foodDescription and calls saveMeal with all-default context values.

struct VoiceMealLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: MealLogViewModel
    let selectedDate: Date

    @State private var pulseScale: CGFloat = 1.0

    private var canFinalizeVoiceLog: Bool {
        !viewModel.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                instructionSection

                Spacer()

                micSection

                Spacer()

                transcriptSection

                Spacer()

                if viewModel.isLoading {
                    loadingPill
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
        .navigationTitle("Speak your meal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("Try Again") { viewModel.startVoiceAutoLog(selectedDate: selectedDate) }
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
            Text("Cadence needs microphone and speech recognition access. Enable both in Settings > Privacy.")
        }
        .onAppear {
            viewModel.startVoiceAutoLog(selectedDate: selectedDate)
        }
        .onDisappear {
            viewModel.cancelVoiceAutoLog()
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
                    pulseScale = 1.18
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pulseScale = 1.0
                }
            }
        }
    }

    // MARK: - Instruction

    private var instructionSection: some View {
        VStack(spacing: 6) {
            Text("Say the dish name and amount")
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
            Text("e.g. \"Avocado toast, 200 grams\"")
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary)
                .italic()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                HapticService.impact(.light)
                viewModel.cancelVoiceAutoLog()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(7)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .disabled(viewModel.isLoading)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                HapticService.impact(.medium)
                if viewModel.isTranscribing {
                    viewModel.stopVoiceAutoLog()
                }
            } label: {
                Text("Save")
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(canFinalizeVoiceLog && !viewModel.isLoading ? AppColors.brand : AppColors.textSecondary)
            }
            .disabled(!canFinalizeVoiceLog || viewModel.isLoading)
        }
    }

    private var loadingPill: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
            Text("Logging your meal…")
                .font(.r(.subheadline, .medium))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 10, y: 3)
        )
    }

    // MARK: - Mic

    private var micSection: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(AppColors.primary.opacity(0.08))
                .frame(width: 160, height: 160)
                .scaleEffect(viewModel.isTranscribing ? pulseScale : 1.0)

            // Inner pulse ring
            Circle()
                .fill(AppColors.primary.opacity(0.14))
                .frame(width: 130, height: 130)
                .scaleEffect(viewModel.isTranscribing ? pulseScale * 0.95 : 1.0)

            // Mic circle
            Circle()
                .fill(viewModel.isTranscribing ? AppColors.primary : AppColors.primaryContainer)
                .frame(width: 104, height: 104)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isTranscribing)

            micIcon
        }
    }

    @ViewBuilder
    private var micIcon: some View {
        if #available(iOS 17, *) {
            Image(systemName: "mic.fill")
                .font(.system(size: 42))
                .foregroundColor(viewModel.isTranscribing ? .white : AppColors.primary)
                .symbolEffect(.variableColor.iterative, isActive: viewModel.isTranscribing)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isTranscribing)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 42))
                .foregroundColor(viewModel.isTranscribing ? .white : AppColors.primary)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isTranscribing)
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptSection: some View {
        if viewModel.isTranscribing || !viewModel.liveTranscript.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.primary)
                Text(viewModel.liveTranscript.isEmpty ? "Listening…" : viewModel.liveTranscript)
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(viewModel.liveTranscript.isEmpty
                                     ? AppColors.textSecondary
                                     : AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 10, y: 3)
            )
            .padding(.horizontal, 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeInOut(duration: 0.2), value: viewModel.liveTranscript)
        }
    }

}
