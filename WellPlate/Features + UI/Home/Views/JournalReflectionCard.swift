import SwiftUI

// MARK: - JournalReflectionCard
//
// Inline card that replaces MoodCheckInCard after mood is logged.
// Compact (~120pt) with a quick text field for a 1–2 line entry.
// "Write more" opens the full JournalEntryView sheet.

struct JournalReflectionCard: View {
    let prompt: String?
    let promptCategory: String?
    @Binding var entryText: String
    var onSave: () -> Void
    var onWriteMore: () -> Void
    var isGeneratingPrompt: Bool

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.brand)

                Text("Daily Reflection")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if let category = promptCategory {
                    Text(category)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.brand)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(AppColors.brand.opacity(0.12))
                        )
                }
            }

            // Prompt
            Group {
                if isGeneratingPrompt {
                    promptShimmer
                } else if let prompt {
                    Text("\u{201C}\(prompt)\u{201D}")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Journal prompt: \(prompt)")
                } else {
                    Text("What's on your mind today?")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }

            // Text field
            TextField("Write something...", text: $entryText, axis: .vertical)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .lineLimit(2...4)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            // Actions
            HStack {
                Button(action: {
                    HapticService.impact(.light)
                    isTextFieldFocused = false
                    onSave()
                }) {
                    Text("Save")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(entryText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AppColors.brand.opacity(0.4)
                                : AppColors.brand)
                        )
                }
                .disabled(entryText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Save journal entry")

                Spacer()

                Button(action: {
                    HapticService.impact(.light)
                    isTextFieldFocused = false
                    onWriteMore()
                }) {
                    HStack(spacing: 4) {
                        Text("Write more")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AppColors.brand)
                }
                .accessibilityLabel("Open full journal editor")
                .accessibilityHint("Write a longer entry")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.08, saturation: 0.12, brightness: 1.0).opacity(0.08),
                            Color(hue: 0.55, saturation: 0.08, brightness: 1.0).opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
    }

    // MARK: - Shimmer placeholder

    private var promptShimmer: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemFill))
                .frame(height: 12)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemFill))
                .frame(height: 12)
                .frame(maxWidth: 180)
        }
        .opacity(0.6)
    }
}

// MARK: - Preview

#Preview("Journal Reflection Card") {
    struct PreviewWrapper: View {
        @State private var text = ""
        var body: some View {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                JournalReflectionCard(
                    prompt: "What's one thing you're grateful for right now?",
                    promptCategory: "gratitude",
                    entryText: $text,
                    onSave: {},
                    onWriteMore: {},
                    isGeneratingPrompt: false
                )
                .padding(.horizontal, 16)
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Loading state") {
    struct PreviewWrapper: View {
        @State private var text = ""
        var body: some View {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                JournalReflectionCard(
                    prompt: nil,
                    promptCategory: nil,
                    entryText: $text,
                    onSave: {},
                    onWriteMore: {},
                    isGeneratingPrompt: true
                )
                .padding(.horizontal, 16)
            }
        }
    }
    return PreviewWrapper()
}
