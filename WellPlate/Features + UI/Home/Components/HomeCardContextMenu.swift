import SwiftUI

// MARK: - HomeCardContextMenu

/// ViewModifier that adds a long-press context menu to home screen cards.
/// Provides Hide, Customize (for compound cards), and navigation to layout editor.
struct HomeCardContextMenu: ViewModifier {
    let card: HomeCardID
    @Binding var layout: HomeLayoutConfig
    let hasHiddenCards: Bool
    var onCustomize: (() -> Void)? = nil
    var onShowLayoutEditor: (() -> Void)? = nil
    var onHide: ((HomeCardID) -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(role: .destructive) {
                    onHide?(card)
                } label: {
                    Label("Hide Card", systemImage: "eye.slash")
                }

                if card.hasSubElements {
                    Button {
                        onCustomize?()
                    } label: {
                        Label("Customize \(card.displayName)", systemImage: "slider.horizontal.3")
                    }
                }

                Divider()

                if hasHiddenCards {
                    Button {
                        onShowLayoutEditor?()
                    } label: {
                        Label("Manage Layout...", systemImage: "square.grid.2x2")
                    }
                }
            }
    }
}

extension View {
    func homeCardMenu(
        card: HomeCardID,
        layout: Binding<HomeLayoutConfig>,
        hasHiddenCards: Bool,
        onCustomize: (() -> Void)? = nil,
        onShowLayoutEditor: (() -> Void)? = nil,
        onHide: ((HomeCardID) -> Void)? = nil
    ) -> some View {
        modifier(HomeCardContextMenu(
            card: card,
            layout: layout,
            hasHiddenCards: hasHiddenCards,
            onCustomize: onCustomize,
            onShowLayoutEditor: onShowLayoutEditor,
            onHide: onHide
        ))
    }
}
