import Foundation
import Combine
import SwiftData

@MainActor
final class GoalsViewModel: ObservableObject {

    @Published var goals: UserGoals

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.goals = UserGoals.current(in: modelContext)
    }

    func save() {
        try? modelContext.save()
    }

    func resetToDefaults() {
        goals.resetToDefaults()
        save()
    }
}
