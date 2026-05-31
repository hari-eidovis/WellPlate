import SwiftUI

struct SplashScreenView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false
    @State private var bouncingOffset: [CGFloat] = Array(repeating: 0, count: 7)
    
  var body: some View {
        ZStack {
            // Adaptive background
            backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 50) {
                Spacer()
                // App name with highlighted text
                VStack(spacing: 16) {
                    HStack(spacing: 0){
                        Text("Well")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(primaryTextColor)
                        Text("Plate")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                    }
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : -20)
                    .animation(.easeOut(duration: 0.6), value: isAnimating)
                    
                    // Tagline with highlighted word
                    HStack(spacing: 8) {
                        Text("Track your")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundColor(primaryTextColor)
                        
                        Text("nutrition")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(accentColor)
                            )
                    }
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : -20)
                    .animation(.easeOut(duration: 0.6).delay(0.2), value: isAnimating)
                    
                    Text("made simple!")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundColor(primaryTextColor)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : -20)
                        .animation(.easeOut(duration: 0.6).delay(0.3), value: isAnimating)
                }
                
                Spacer()
                Spacer()
                
                // Characters at the bottom - matching NutriAI layout
                ZStack {
                    // Character arrangement
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        
                        // Blue Triangle (left, upper)
                        characterView(imageName: "Group 11", index: 0)
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(-20))
                            .position(x: width * 0.20, y: 100)
                        
                        // Green Today pill (left, lower)
                        characterView(imageName: "Today", index: 1)
                            .frame(width: 80, height: 130)
                            .rotationEffect(.degrees(15))
                            .position(x: width * 0.15, y: 230)
                        
                        // Orange rectangle (center-left)
                        characterView(imageName: "Group 18", index: 2)
                            .frame(width: 120, height: 160)
                            .rotationEffect(.degrees(-12))
                            .position(x: width * 0.35, y: 250)
                        
                        // Green square (center)
                        characterView(imageName: "Group 10", index: 3)
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(8))
                            .position(x: width * 0.52, y: 170)
                        
                        // Pink Heart (center-right, lower)
                        characterView(imageName: "Group 16", index: 4)
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(-5))
                            .position(x: width * 0.62, y: 280)
                        
                        // Yellow square (right, upper)
                        characterView(imageName: "Group 17", index: 5)
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(18))
                            .position(x: width * 0.78, y: 90)
                        
                        // Purple pill (right, middle)
                        characterView(imageName: "Group 9", index: 6)
                            .frame(width: 155, height: 150)
                            .rotationEffect(.degrees(-10))
                            .position(x: width * 0.85, y: 200)
                    }
                }
                .offset(x: 5, y: 100)
            }
        }
        .onAppear {
            isAnimating = true
            startBouncing()
        }
    }
    
    // MARK: - Adaptive Colors
    
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.12)
            : Color.white
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark
            ? .white
            : Color(red: 0.2, green: 0.2, blue: 0.2)
    }
    
    private var accentColor: Color {
        Color(red: 1.0, green: 0.45, blue: 0.25)
    }
    
    // MARK: - Character View
    
    private func characterView(imageName: String, index: Int) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .offset(y: bouncingOffset[index])
            .opacity(isAnimating ? 1 : 0)
            .scaleEffect(isAnimating ? 1 : 0.3)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.7)
                .delay(Double(index) * 0.1),
                value: isAnimating
            )
    }
// MARK: - Bouncing Animation
    private func startBouncing() {
        for index in 0..<7 {
            let delay = Double(index) * 0.2
            let duration = 1.5 + Double.random(in: -0.2...0.2)
            
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    bouncingOffset[index] = CGFloat.random(in: -8...8)
                }
            }
        }
    }
}

// MARK: - Helper Shapes
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct WavyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.midY),
            control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.maxY)
        )
        return path
    }
}

// MARK: - Preview
struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SplashScreenView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            SplashScreenView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
