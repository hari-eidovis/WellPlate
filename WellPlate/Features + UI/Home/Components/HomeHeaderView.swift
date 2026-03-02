import SwiftUI

struct HomeHeaderView: View {
    let selectedDate: Date
    let currentStreak: Int
    var onDateTap: () -> Void
    var onStreakTap: () -> Void
    var onChartTap: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            // Left: Greeting + date
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.r(.title3, .semibold))
                    .foregroundColor(.primary)

                Button(action: {
                    HapticService.impact(.light)
                    onDateTap()
                }) {
                    HStack(spacing: 4) {
                        Text(dateText)
                            .font(.r(.subheadline, .medium))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Right: Streak + chart buttons
            HStack(spacing: 14) {
                Button(action: {
                    HapticService.impact(.light)
                    onStreakTap()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("\(currentStreak)")
                            .font(.r(16, .semibold))
                            .foregroundColor(.primary)
                    }
                }

                Button(action: {
                    HapticService.impact(.light)
                    onChartTap()
                }) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 8, y: 2)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else if calendar.isDateInTomorrow(selectedDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: selectedDate)
        }
    }
}
