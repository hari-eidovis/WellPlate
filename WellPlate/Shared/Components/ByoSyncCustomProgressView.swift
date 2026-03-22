import SwiftUI

// MARK: - 1. Breathing Logo Loader (Subtle scale animation)
struct BreathingLogoLoader: View {
    @State private var isAnimating = false
    let size: CGFloat
    
    init(size: CGFloat = 80) {
        self.size = size
    }
    
    var body: some View {
        Image("logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.1 : 0.95)
            .opacity(isAnimating ? 1.0 : 0.7)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - 2. Rotating Logo Loader (Smooth rotation)
struct RotatingLogoLoader: View {
    @State private var isRotating = false
    let size: CGFloat
    
    init(size: CGFloat = 40) {
        self.size = size
    }
    
    var body: some View {
        Image("logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(
                .linear(duration: 2.0)
                .repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear {
                isRotating = true
            }
    }
}

// MARK: - 3. Shimmer Logo Loader (Glowing effect)
struct ShimmerLogoLoader: View {
    @State private var phase: CGFloat = 0
    let size: CGFloat
    
    init(size: CGFloat = 80) {
        self.size = size
    }
    
    var body: some View {
        Image("logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.4),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .mask(
                    Image("logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                )
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = size * 2
                }
            }
    }
}

// MARK: - 4. Pulsing Logo with Rings (Ripple effect)
struct PulsingLogoLoader: View {
    @State private var isPulsing = false
    let size: CGFloat
    
    init(size: CGFloat = 80) {
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "4169E1"), Color(hex: "8A2BE2")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)
            
            // Inner ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "4169E1"), Color(hex: "8A2BE2")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: size * 1.2, height: size * 1.2)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .opacity(isPulsing ? 0 : 0.8)
            
            // Logo
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
        .animation(
            .easeOut(duration: 1.5)
            .repeatForever(autoreverses: false),
            value: isPulsing
        )
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - 5. Logo with Progress Bar (For determinate progress)
struct LogoProgressBar: View {
    let progress: Double // 0.0 to 1.0
    let size: CGFloat
    
    init(progress: Double, size: CGFloat = 80) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.size = size
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "4169E1"), Color(hex: "8A2BE2")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: progress)
                }
            }
            .frame(height: 6)
            .frame(width: size * 2)
            
            // Progress text
            Text("\(Int(progress * 100))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .onChange(of: progress) { _, _ in }
    }
}

// MARK: - 6. Minimal Spinning Arc with Logo
struct SpinningArcLoader: View {
    @State private var isRotating = false
    let size: CGFloat
    
    init(size: CGFloat = 80) {
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Spinning arc
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "4169E1"), Color(hex: "8A2BE2")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: size * 1.3, height: size * 1.3)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false),
                    value: isRotating
                )
            
            // Logo
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .onAppear {
            isRotating = true
        }
    }
}

// MARK: - 7. Three Dots with Logo (Simple loading)
struct ThreeDotsLoader: View {
    @State private var animatingDot = 0
    let size: CGFloat
    
    init(size: CGFloat = 80) {
        self.size = size
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
            
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "4169E1"), Color(hex: "8A2BE2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 8, height: 8)
                        .scaleEffect(animatingDot == index ? 1.3 : 0.8)
                        .opacity(animatingDot == index ? 1.0 : 0.5)
                }
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                animatingDot = (animatingDot + 1) % 3
            }
        }
    }
}

// MARK: - 8. Full Screen Loading Overlay
struct FullScreenLogoLoader: View {
    let loaderType: LoaderType
    let message: String?
    
    enum LoaderType {
        case breathing
        case rotating
        case shimmer
        case pulsing
        case spinningArc
    }
    
    init(type: LoaderType = .breathing, message: String? = nil) {
        self.loaderType = type
        self.message = message
    }
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Glass card with loader
            VStack(spacing: 20) {
                Group {
                    switch loaderType {
                    case .breathing:
                        BreathingLogoLoader(size: 100)
                    case .rotating:
                        RotatingLogoLoader(size: 100)
                    case .shimmer:
                        ShimmerLogoLoader(size: 100)
                    case .pulsing:
                        PulsingLogoLoader(size: 100)
                    case .spinningArc:
                        SpinningArcLoader(size: 100)
                    }
                }
                
                if let message = message {
                    Text(message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
}

// MARK: - Helper Extension for Hex Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview Provider
#Preview("All Loaders") {
    ScrollView {
        VStack(spacing: 40) {
            VStack(spacing: 8) {
                Text("Breathing Logo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                BreathingLogoLoader()
            }
            
            VStack(spacing: 8) {
                Text("Rotating Logo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                RotatingLogoLoader()
            }
            
            VStack(spacing: 8) {
                Text("Shimmer Logo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ShimmerLogoLoader()
            }
            
            VStack(spacing: 8) {
                Text("Pulsing Logo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                PulsingLogoLoader()
            }
            
            VStack(spacing: 8) {
                Text("Spinning Arc")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SpinningArcLoader()
            }
            
            VStack(spacing: 8) {
                Text("Three Dots")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ThreeDotsLoader()
            }
            
            VStack(spacing: 8) {
                Text("Progress Bar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                LogoProgressBar(progress: 0.65)
            }
        }
        .padding()
    }
    .background(Color(.systemBackground))
}

#Preview("Full Screen Overlay") {
    ZStack {
        Color.blue.ignoresSafeArea()
        
        FullScreenLogoLoader(type: .pulsing, message: "Loading your profile...")
    }
}
