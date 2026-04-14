import SwiftUI

// MARK: - UndoToast

/// Auto-dismissing toast with undo action. Appears at the bottom of the screen.
/// Uses `dismissID` to prevent stale timers from dismissing a newer toast.
struct UndoToast: View {
    let message: String
    let dismissID: UUID
    let onUndo: () -> Void
    let onDismiss: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Button {
                HapticService.impact(.light)
                onUndo()
            } label: {
                Text("Undo")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(.darkGray))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            let id = dismissID
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.25)) {
                    onDismiss(id)
                }
            }
        }
    }
}
