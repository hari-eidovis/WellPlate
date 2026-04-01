import SwiftUI

struct WellnessReportData {
    let dateRange: String
    let avgStressScore: Double?
    let avgCalories: Double
    let calorieGoal: Int
    let avgProtein: Double
    let avgCarbs: Double
    let avgFat: Double
    let avgSteps: Double
    let avgWaterGlasses: Double
    let waterGoal: Int
    let dominantMoodEmoji: String
    let loggedDays: Int
}

@MainActor
struct WellnessReportGenerator {

    /// Renders WellnessReportView to a JPEG-compressed UIImage.
    static func renderImage(data: WellnessReportData) async -> UIImage? {
        let view = WellnessReportView(data: data)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let uiImage = renderer.uiImage else { return nil }
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.88) else { return uiImage }
        return UIImage(data: jpegData) ?? uiImage
    }

    /// Generates a UTF-8 CSV Data blob from the raw log entries.
    static func generateCSV(
        foodLogs: [FoodLogEntry],
        stressReadings: [StressReading],
        wellnessLogs: [WellnessDayLog]
    ) -> Data {
        var rows: [String] = ["date,stress_score,calories,protein_g,carbs_g,fat_g,steps,water_glasses,mood"]

        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        let daySeq: [Date] = (0..<7).compactMap {
            cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date()))
        }.reversed()

        let foodByDay    = Dictionary(grouping: foodLogs.filter { $0.day >= cutoff }) { $0.day }
        let stressByDay  = Dictionary(grouping: stressReadings.filter { $0.timestamp >= cutoff }) { $0.day }
        let wellnessByDay = Dictionary(grouping: wellnessLogs.filter { $0.day >= cutoff }) { $0.day }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        for day in daySeq {
            let food     = foodByDay[day] ?? []
            let stress   = stressByDay[day]
            let wellness = wellnessByDay[day]?.first

            let calories  = food.reduce(0) { $0 + $1.calories }
            let protein   = food.reduce(0.0) { $0 + $1.protein }
            let carbs     = food.reduce(0.0) { $0 + $1.carbs }
            let fat       = food.reduce(0.0) { $0 + $1.fat }
            let stressAvg = stress.map { r in r.map(\.score).reduce(0, +) / Double(r.count) }
            let steps     = wellness?.steps ?? 0
            let water     = wellness?.waterGlasses ?? 0
            let mood      = wellness?.mood?.label ?? ""

            let stressStr = stressAvg.map { String(format: "%.1f", $0) } ?? ""
            let row = "\(dateFmt.string(from: day)),\(stressStr),\(calories),\(String(format: "%.1f", protein)),\(String(format: "%.1f", carbs)),\(String(format: "%.1f", fat)),\(steps),\(water),\(mood)"
            rows.append(row)
        }

        return rows.joined(separator: "\n").data(using: .utf8) ?? Data()
    }
}
