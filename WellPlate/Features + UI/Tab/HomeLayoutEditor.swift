import SwiftUI

struct HomeLayoutEditor: View {
    @Binding var layout: HomeLayoutConfig
    @State private var showResetAlert = false

    private var visibleCards: [HomeCardID] {
        layout.cardOrder.filter { !layout.hiddenCards.contains($0) }
    }

    private var hiddenCards: [HomeCardID] {
        layout.cardOrder.filter { layout.hiddenCards.contains($0) }
    }

    var body: some View {
        List {
            // Visible cards — reorderable
            Section {
                ForEach(visibleCards, id: \.self) { card in
                    cardRow(card, isVisible: true)
                }
                .onMove { source, destination in
                    moveVisibleCards(from: source, to: destination)
                }
                .deleteDisabled(true)
            } header: {
                Text("Visible Cards")
            } footer: {
                Text("Drag to reorder. Cards appear on your home screen in this order.")
                    .font(.system(size: 12, design: .rounded))
            }

            // Hidden cards
            if !hiddenCards.isEmpty {
                Section("Hidden Cards") {
                    ForEach(hiddenCards, id: \.self) { card in
                        cardRow(card, isVisible: false)
                    }
                    .deleteDisabled(true)
                }
            }

            // Reset
            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset to Default Layout", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Home Layout")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .alert("Reset Layout?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                withAnimation {
                    layout.reset()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all cards to their default order and visibility.")
        }
    }

    @ViewBuilder
    private func cardRow(_ card: HomeCardID, isVisible: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: card.iconName)
                .font(.system(size: 16))
                .foregroundStyle(isVisible ? .primary : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(isVisible ? .primary : .secondary)

                if card.hasSubElements {
                    let visible = layout.visibleElements(for: card)
                    let total = card.subElements.count
                    Text("\(visible.count)/\(total) elements visible")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                // TODO: Future — add NavigationLink for element-level customisation from here
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isVisible {
                        layout.hideCard(card)
                    } else {
                        layout.showCard(card)
                    }
                }
            } label: {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(isVisible ? AppColors.brand : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func moveVisibleCards(from source: IndexSet, to destination: Int) {
        var visible = visibleCards
        visible.move(fromOffsets: source, toOffset: destination)

        var newOrder: [HomeCardID] = visible
        for card in layout.cardOrder where layout.hiddenCards.contains(card) {
            newOrder.append(card)
        }
        layout.cardOrder = newOrder
    }
}
