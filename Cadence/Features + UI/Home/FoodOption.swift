import Foundation

// MARK: - FoodOption
//
// A concrete food interpretation surfaced by disambiguation chips.
// Plain struct — no @Generable annotation (FoundationModels types stay in MealCoachService).

struct FoodOption: Identifiable {
    let id: UUID
    let label: String            // e.g. "Thin-crust pizza slice"
    let calorieEstimate: Int     // e.g. 220

    init(label: String, calorieEstimate: Int, id: UUID = UUID()) {
        self.id = id
        self.label = label
        self.calorieEstimate = calorieEstimate
    }
}
