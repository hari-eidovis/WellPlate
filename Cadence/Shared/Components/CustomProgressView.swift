import SwiftUI

struct CustomProgressView: View {
    @State private var bounceStates: [Bool] = Array(repeating: false, count: 3)
    @State private var showText = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 50) {
                // Bouncing food icons
                HStack(spacing: 20) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.25))
                            .frame(width: 20, height: 20)
                            .offset(y: bounceStates[index] ? -30 : 0)
                            .animation(
                                .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                                value: bounceStates[index]
                            )
                    }
                }
            
                VStack(spacing: 8) {
                    
                    Text("Getting things ready...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .opacity(showText ? 1 : 0)
            }
        }
        .onAppear {
            for index in 0..<3 {
                bounceStates[index] = true
            }

            withAnimation(.easeOut(duration: 0.6)) {
                showText = true
            }
        }
    }
}

#Preview("Light") {
    CustomProgressView()
}

#Preview("Dark") {
    CustomProgressView()
        .preferredColorScheme(.dark)
}
