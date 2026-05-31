import SwiftUI

// MARK: - JournalEntryView
//
// Full journal sheet for deeper reflection.
// Save is handled exclusively via onSave callback (parent sets activeSheet = nil).
// X button uses dismiss() for cancel only.

struct JournalEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let mood: MoodOption?
    let stressLevel: String?
    @Binding var entryText: String
    let prompt: String?
    @ObservedObject var promptService: JournalPromptService
    var onSave: () -> Void

    private let characterLimit = 2000

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var isSaveDisabled: Bool {
        entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var characterCountColor: Color {
        entryText.count > 1800 ? Color.orange : Color.secondary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Context header
                    contextHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Prompt card
                    promptCard
                        .padding(.horizontal, 20)

                    // Text editor
                    textEditorSection
                        .padding(.horizontal, 20)

                    // Character count
                    HStack {
                        Spacer()
                        Text("\(entryText.count) / \(characterLimit)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(characterCountColor)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Daily Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Cancel and close")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticService.impact(.light)
                        onSave()
                        // Note: do NOT call dismiss() here — parent handles sheet dismissal via activeSheet = nil
                    } label: {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSaveDisabled ? AppColors.brand.opacity(0.4) : AppColors.brand)
                    }
                    .disabled(isSaveDisabled)
                    .accessibilityLabel("Save journal entry")
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Context Header

    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateString)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let mood {
                    HStack(spacing: 4) {
                        Text(mood.emoji)
                            .font(.system(size: 16))
                        Text(mood.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(mood.accentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(mood.accentColor.opacity(0.12))
                    )
                    .accessibilityLabel("Mood: \(mood.label)")
                }

                if let stressLevel {
                    Text("Stress: \(stressLevel)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
    }

    // MARK: - Prompt Card

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if promptService.isGenerating {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemFill)).frame(height: 14).frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemFill)).frame(height: 14).frame(maxWidth: 200)
                }
                .opacity(0.6)
            } else if let p = promptService.currentPrompt ?? prompt {
                Text("\u{201C}\(p)\u{201D}")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Journal prompt: \(p)")
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Text Editor

    private var textEditorSection: some View {
        ZStack(alignment: .topLeading) {
            if entryText.isEmpty {
                Text("Write your thoughts here...")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(.placeholderText))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $entryText)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 200)
                .onChange(of: entryText) { _, newValue in
                    if newValue.count > characterLimit {
                        entryText = String(newValue.prefix(characterLimit))
                    }
                }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Preview

#Preview("Journal Entry View") {
    struct PreviewWrapper: View {
        @State private var text = ""
        @StateObject private var promptService = JournalPromptService()
        var body: some View {
            JournalEntryView(
                mood: .good,
                stressLevel: "Moderate",
                entryText: $text,
                prompt: "What's one thing you're grateful for right now?",
                promptService: promptService,
                onSave: {}
            )
        }
    }
    return PreviewWrapper()
}
