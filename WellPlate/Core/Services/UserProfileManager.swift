import Foundation

/// Manages user profile data stored in `UserDefaults`.
/// Weight is stored internally in **kg**, height in **cm**.
/// Display conversion is performed at the view layer via the unit preference.
final class UserProfileManager {
    static let shared = UserProfileManager()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case hasCompletedOnboarding
        case userName
        case userWeight      // always kg
        case userHeight      // always cm
        case weightUnit      // "kg" | "lbs"
        case heightUnit      // "cm" | "ft"
    }

    // MARK: - Onboarding Gate

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding.rawValue) }
    }

    // MARK: - Name

    var userName: String {
        get { defaults.string(forKey: Key.userName.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.userName.rawValue) }
    }

    // MARK: - Weight (stored in kg)

    /// Raw weight in kilograms.
    var weightKg: Double {
        get { defaults.double(forKey: Key.userWeight.rawValue) }
        set { defaults.set(newValue, forKey: Key.userWeight.rawValue) }
    }

    var weightUnit: WeightUnit {
        get {
            let raw = defaults.string(forKey: Key.weightUnit.rawValue) ?? WeightUnit.kg.rawValue
            return WeightUnit(rawValue: raw) ?? .kg
        }
        set { defaults.set(newValue.rawValue, forKey: Key.weightUnit.rawValue) }
    }

    /// Display weight in the user's preferred unit.
    var displayWeight: Double {
        switch weightUnit {
        case .kg:  return weightKg
        case .lbs: return weightKg * 2.20462
        }
    }

    /// Set weight from user's preferred unit (converts to kg for storage).
    func setWeight(_ value: Double, unit: WeightUnit) {
        weightUnit = unit
        switch unit {
        case .kg:  weightKg = value
        case .lbs: weightKg = value / 2.20462
        }
    }

    // MARK: - Height (stored in cm)

    /// Raw height in centimeters.
    var heightCm: Double {
        get { defaults.double(forKey: Key.userHeight.rawValue) }
        set { defaults.set(newValue, forKey: Key.userHeight.rawValue) }
    }

    var heightUnit: HeightUnit {
        get {
            let raw = defaults.string(forKey: Key.heightUnit.rawValue) ?? HeightUnit.cm.rawValue
            return HeightUnit(rawValue: raw) ?? .cm
        }
        set { defaults.set(newValue.rawValue, forKey: Key.heightUnit.rawValue) }
    }

    /// Display height in the user's preferred unit.
    var displayHeight: Double {
        switch heightUnit {
        case .cm: return heightCm
        case .ft: return heightCm / 30.48  // returns decimal feet
        }
    }

    /// Formatted height string (e.g. "175 cm" or "5'9\"").
    var formattedHeight: String {
        switch heightUnit {
        case .cm:
            return "\(Int(heightCm)) cm"
        case .ft:
            let totalInches = heightCm / 2.54
            let feet = Int(totalInches) / 12
            let inches = Int(totalInches) % 12
            return "\(feet)'\(inches)\""
        }
    }

    /// Set height from user's preferred unit (converts to cm for storage).
    func setHeight(_ value: Double, unit: HeightUnit) {
        heightUnit = unit
        switch unit {
        case .cm: heightCm = value
        case .ft: heightCm = value * 30.48
        }
    }

    /// Formatted weight string (e.g. "70 kg" or "154 lbs").
    var formattedWeight: String {
        "\(Int(displayWeight)) \(weightUnit.rawValue)"
    }

    // MARK: - Defaults

    /// Apply sensible defaults for first-time setup.
    func applyDefaults() {
        if weightKg == 0 { weightKg = 70.0 }
        if heightCm == 0 { heightCm = 170.0 }
    }

    private init() {}
}

// MARK: - Unit Enums

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg  = "kg"
    case lbs = "lbs"
    var id: String { rawValue }
}

enum HeightUnit: String, CaseIterable, Identifiable {
    case cm = "cm"
    case ft = "ft"
    var id: String { rawValue }
}
