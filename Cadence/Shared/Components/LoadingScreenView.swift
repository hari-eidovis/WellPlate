import SwiftUI

struct LoadingScreenView: View {
    @State private var fillProgress: CGFloat = 0
    @State private var showText = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // App name
                HStack(spacing: 0) {
                    Text("Well")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Plate")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.25))
                }
                .opacity(showText ? 1 : 0)
                .scaleEffect(showText ? 1 : 0.8)
                
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.25).opacity(0.2))
                        .frame(width: 130, height: 8)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.25))
                        .frame(width: 130 * fillProgress, height: 8)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: fillProgress)
                }
                
//                Text("Preparing your healthy journey...")
//                    .font(.system(size: 14, weight: .medium))
//                    .foregroundColor(.gray)
//                    .opacity(showText ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showText = true
            }
            
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                fillProgress = 1.0
            }
        }
    }
}

#Preview("Light") {
    LoadingScreenView()
}

#Preview("Dark") {
    LoadingScreenView()
        .preferredColorScheme(.dark)
}
