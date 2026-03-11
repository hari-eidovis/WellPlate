import SwiftUI

struct DragToLogOverlay: View {
    let onTrigger: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var hasTickedHalf = false
    @State private var isVisible = false
    @State private var pulseOpacity: Double = 0.5

    private let dragThreshold: CGFloat = 100

    var body: some View {
        VStack(spacing: 8) {
            
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.primary.opacity(0.7))
            
            HStack(spacing: 6) {
                Text("Log a meal")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(pulseOpacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .offset(y: min(0, dragOffset))
        .scaleEffect(
            1 + min(0.04, max(0, -dragOffset) / dragThreshold * 0.04),
            anchor: .bottom
        )
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let t = value.translation
                    guard t.height < 0, abs(t.width) < abs(t.height) else { return }

                    dragOffset = t.height

                    if !hasTickedHalf && -t.height >= dragThreshold / 2 {
                        HapticService.selectionChanged()
                        hasTickedHalf = true
                    }
                }
                .onEnded { value in
                    let t = value.translation.height
                    if -t >= dragThreshold {
                        HapticService.impact(.medium)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                        onTrigger()
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                    }
                    hasTickedHalf = false
                }
        )
        .onTapGesture {
            HapticService.impact(.medium)
            onTrigger()
        }
        .accessibilityLabel("Log a meal")
        .accessibilityHint("Opens the meal logging form")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            isVisible = true
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulseOpacity = 1.0
            }
        }
        .onDisappear {
            isVisible = false
            pulseOpacity = 0.5
        }
    }
}

#Preview("Drag Overlay") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        DragToLogOverlay {}
    }
}

#Preview("Drag Overlay - Dark") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        DragToLogOverlay {}
    }
    .preferredColorScheme(.dark)
}
