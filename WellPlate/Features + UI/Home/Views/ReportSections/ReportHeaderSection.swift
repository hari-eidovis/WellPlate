import SwiftUI

struct ReportHeaderSection: View {
    let data: ReportData

    private var dateRangeText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let start = f.string(from: data.context.days.first?.date ?? .now)
        let end = f.string(from: data.context.days.last?.date ?? .now)
        let year = Calendar.current.component(.year, from: .now)
        return "\(start) — \(end), \(year)"
    }

    private var daysWithData: Int {
        data.context.days.filter { d in
            d.stressScore != nil || d.totalCalories != nil || d.sleepHours != nil || d.steps != nil
        }.count
    }

    private var domainCount: Int {
        var count = 0
        let days = data.context.days
        if days.contains(where: { $0.stressScore != nil }) { count += 1 }
        if days.contains(where: { $0.totalCalories != nil }) { count += 1 }
        if days.contains(where: { $0.sleepHours != nil }) { count += 1 }
        if days.contains(where: { $0.steps != nil }) { count += 1 }
        if days.contains(where: { ($0.waterGlasses ?? 0) > 0 }) { count += 1 }
        if days.contains(where: { !$0.symptomNames.isEmpty }) { count += 1 }
        if days.contains(where: { $0.supplementAdherence != nil }) { count += 1 }
        if days.contains(where: { $0.fastingHours != nil }) { count += 1 }
        if days.contains(where: { $0.moodLabel != nil }) { count += 1 }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
                Text("WELLNESS REPORT")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.brand)
                    .tracking(1.2)
            }

            Text("Your 15-Day Wellness Report")
                .font(.r(.title3, .bold))
                .foregroundStyle(.primary)

            Text(dateRangeText)
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)

            Text("Based on \(daysWithData) days of data across \(domainCount) domains")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.brand.opacity(0.08))
        )
    }
}
