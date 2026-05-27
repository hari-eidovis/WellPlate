import SwiftUI

// MARK: - TeaTypePickerSheet
// Half-sheet presented when the user logs a generic "tea" / "chai" meal entry,
// so the canonical food name can be refined into a specific variant.
// onSelect is called with the chosen TeaType; the caller is responsible for
// dismissing the sheet (by clearing the bound state).

struct TeaTypePickerSheet: View {
    var onSelect: (TeaType) -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("What kind of tea?")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.top, 8)

                    Text("Pick the closest match")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(TeaType.allCases) { type in
                            TeaTypeCell(type: type) {
                                onSelect(type)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Choose Tea")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - TeaTypeCell

private struct TeaTypeCell: View {
    let type: TeaType
    let action: () -> Void

    private let teaColor      = Color(hue: 0.32, saturation: 0.55, brightness: 0.55)
    private let teaColorLight = Color(hue: 0.32, saturation: 0.18, brightness: 0.97)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: type.symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(teaColor)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(teaColorLight)
                    )

                Text(type.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    TeaTypePickerSheet { type in
        print("Selected: \(type.displayName)")
    }
}
