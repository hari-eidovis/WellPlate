import SwiftUI

struct HiddenCardsPill: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count) card\(count == 1 ? "" : "s") hidden")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }
}
