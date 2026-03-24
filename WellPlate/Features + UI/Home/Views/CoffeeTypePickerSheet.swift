import SwiftUI

// MARK: - CoffeeTypePickerSheet
// Half-sheet presented on the user's first cup of each new day.
// onSelect is called with the chosen CoffeeType; the caller is responsible for
// dismissing the sheet (by setting the isPresented binding to false).

struct CoffeeTypePickerSheet: View {
    var onSelect: (CoffeeType) -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            // ScrollView prevents clipping on small screens (4.7" SE at .medium detent).
            ScrollView {
                VStack(spacing: 20) {
                    Text("What are you drinking?")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.top, 8)

                    Text("Each selection counts as 1 cup")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(CoffeeType.allCases) { type in
                            CoffeeTypeCell(type: type) {
                                onSelect(type)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Choose Coffee")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - CoffeeTypeCell

private struct CoffeeTypeCell: View {
    let type: CoffeeType
    let action: () -> Void

    private let coffeeColor      = Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
    private let coffeeColorLight = Color(hue: 0.08, saturation: 0.25, brightness: 0.97)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: type.symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(coffeeColor)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(coffeeColorLight)
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
    CoffeeTypePickerSheet { type in
        print("Selected: \(type.displayName)")
    }
}
