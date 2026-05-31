import SwiftUI

struct ExpandableFAB: View {
    let onMicTap: () -> Void
    let onCameraTap: () -> Void
    let onNotepadTap: () -> Void

    @State private var isExpanded = false

    private struct ActionItem {
        let icon: String
        let color: Color
        let action: () -> Void
    }

    private var actions: [ActionItem] {
        [
            ActionItem(icon: "mic.fill", color: .pink, action: onMicTap),
            ActionItem(icon: "camera.fill", color: .blue, action: onCameraTap),
            ActionItem(icon: "note.text", color: .green, action: onNotepadTap),
        ]
    }

    var body: some View {
        HStack(spacing: 12) {
            if isExpanded {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, item in
                    Button {
                        HapticService.impact(.light)
                        item.action()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(item.color.gradient)
                            )
                            .shadow(color: item.color.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .scale(scale: 0.3)
                        .combined(with: .opacity)
                        .combined(with: .offset(x: 20))
                    )
                }
            }

            // Main plus button
            Button {
                HapticService.impact(.medium)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.brand, AppColors.brand.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: AppColors.brand.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack {
            Spacer()
            HStack {
                Spacer()
                ExpandableFAB(
                    onMicTap: {},
                    onCameraTap: {},
                    onNotepadTap: {}
                )
                .padding(20)
            }
        }
    }
}
