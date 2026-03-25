import SwiftUI

struct DragToLogOverlay: View {
    let onTrigger: () -> Void
    @Binding var dragProgress: CGFloat

    @State private var dragOffset: CGFloat = 0
    @State private var hasTickedHalf = false
    @State private var isPressed = false

    private let dragThreshold: CGFloat = 80

    var body: some View {
        Button(action: {
            HapticService.impact(.medium)
            onTrigger()
        }) {
            HStack(spacing: 12) {
                    Spacer()
                VStack(spacing: 6){
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("Log a Meal")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 4)
                        )
                }
                    Spacer()
         
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .offset(y: min(0, dragOffset))
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let t = value.translation
                    guard t.height < 0, abs(t.width) < abs(t.height) else { return }
                    dragOffset = t.height
                    dragProgress = min(1.0, -t.height / dragThreshold)
                    if !hasTickedHalf && -t.height >= dragThreshold / 2 {
                        HapticService.selectionChanged()
                        hasTickedHalf = true
                    }
                }
                .onEnded { value in
                    if -value.translation.height >= dragThreshold {
                        HapticService.impact(.medium)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                            dragProgress = 0
                        }
                        onTrigger()
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            dragOffset = 0
                            dragProgress = 0
                        }
                    }
                    hasTickedHalf = false
                }
        )
        .accessibilityLabel("Log a meal")
        .accessibilityHint("Opens the food journal")
        .accessibilityAddTraits(.isButton)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
    }
}

#Preview("Drag Overlay") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        DragToLogOverlay(onTrigger: {}, dragProgress: .constant(0))
            .padding(.bottom, 8)
    }
}

#Preview("Drag Overlay - Dark") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        DragToLogOverlay(onTrigger: {}, dragProgress: .constant(0))
            .padding(.bottom, 8)
    }
    .preferredColorScheme(.dark)
}
