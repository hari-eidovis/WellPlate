import SwiftUI

/// Compact pill that surfaces the HRV/RHR multiplicative calibrator.
///
/// 4 modes:
/// - `vitals-good`     (calibrator < 1.0): "Vitals great"
/// - `vitals-strain`   (calibrator > 1.0): "+X% strain"
/// - `vitals-normal`   (calibrator == 1.0 with baseline): "Vitals normal"
/// - `no-baseline`     (Watch-less or insufficient days): "Vitals — no baseline"
struct CalibratorChip: View {
    let calibrator: Double
    let hasBaseline: Bool

    private var label: String {
        guard hasBaseline else { return "Vitals — no baseline" }
        let pct = Int(round((calibrator - 1.0) * 100))
        if calibrator > 1.005 {
            return "+\(pct)% strain"
        } else if calibrator < 0.995 {
            return "\(pct)% recovery"
        } else {
            return "Vitals normal"
        }
    }

    private var icon: String {
        guard hasBaseline else { return "waveform.path.ecg" }
        if calibrator > 1.005 { return "arrow.up.right" }
        if calibrator < 0.995 { return "arrow.down.right" }
        return "waveform.path.ecg"
    }

    private var tint: Color {
        let blue = Color(hex: "5E9FFF")
        guard hasBaseline else { return .secondary }
        if calibrator > 1.005 { return Color.orange }
        if calibrator < 0.995 { return Color.green }
        return blue
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.r(.caption, .semibold))
                .tracking(0.3)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(hasBaseline ? 0.12 : 0.08)))
    }
}

#Preview {
    VStack(spacing: 8) {
        CalibratorChip(calibrator: 1.12, hasBaseline: true)
        CalibratorChip(calibrator: 0.92, hasBaseline: true)
        CalibratorChip(calibrator: 1.0, hasBaseline: true)
        CalibratorChip(calibrator: 1.0, hasBaseline: false)
    }
}
