import SwiftUI

struct QuickAddCard: View {
    @Binding var foodDescription: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.orange.opacity(0.6))

            TextField("Add food...", text: $foodDescription)
                .font(.r(15, .regular))
                .textFieldStyle(.plain)
                .focused(isFocused)
                .disabled(isLoading)
                .tint(.orange)
                .submitLabel(.return)
                .onSubmit {
                    let trimmed = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onSubmit() }
                }

            if !foodDescription.isEmpty {
                Button(action: onSubmit) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .symbolEffect(.breathe, isActive: isLoading)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.orange.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: .orange.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
        .padding(.horizontal, 16)
    }
}
