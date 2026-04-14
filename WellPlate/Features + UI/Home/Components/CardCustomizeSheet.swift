import SwiftUI

// MARK: - CardCustomizeSheet

/// Presents toggle rows for each sub-element of a compound card.
struct CardCustomizeSheet: View {
    let card: HomeCardID
    @Binding var layout: HomeLayoutConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(card.subElements) { element in
                        let isVisible = layout.isElementVisible(element, in: card)
                        Toggle(isOn: Binding(
                            get: { isVisible },
                            set: { _ in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    layout.toggleElement(element, in: card)
                                }
                            }
                        )) {
                            Label(element.displayName, systemImage: element.iconName)
                        }
                    }
                } footer: {
                    Text("Hidden elements won't appear on your home screen. If all elements are hidden, the entire card will be hidden.")
                        .font(.system(size: 12, design: .rounded))
                }
            }
            .navigationTitle("Customize \(card.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
