import SwiftUI

enum AppColors {
    // MARK: - Brand / Primary
    static let brand             = Color("AppPrimary")           // adaptive: reads light/dark from AppPrimary.colorset
    static let primary           = Color("AppPrimary")
    static let primaryContainer  = Color("PrimaryContainer")     // soft green background
    static let onPrimary         = Color("OnPrimary")            // text/icons on primary

    // MARK: - Surfaces / Borders / Text
    static let surface = Color("Surface")
    static let borderSubtle = Color("BorderSubtle")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")

    // MARK: - Status
    static let success = Color("Success")
    static let warning = Color("Warning")
    static let error = Color("Error")
}

enum AppOpacity {
    /// Common UI state opacities (keep these consistent across the app).
    static let disabled: Double = 0.38
    static let pressed: Double = 0.12
    static let overlay: Double = 0.08
}

// MARK: - Convenience helpers (optional)
extension View {
    /// Apply disabled styling consistently (dim + disable interaction).
    func appDisabled(_ disabled: Bool) -> some View {
        self
            .disabled(disabled)
            .opacity(disabled ? AppOpacity.disabled : 1.0)
    }

    /// Adaptive shadow — dark in light mode, subtle white glow in dark mode.
    /// Always pass `y` explicitly; use negative values for upward-projecting shadows.
    func appShadow(radius: CGFloat, x: CGFloat = 0, y: CGFloat) -> some View {
        self.shadow(color: Color(.label).opacity(0.08), radius: radius, x: x, y: y)
    }
}
