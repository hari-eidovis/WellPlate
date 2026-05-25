import SwiftUI
import SwiftData

struct SupplementListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var supplements: [SupplementEntry]
    @Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]
    @ObservedObject var service: SupplementService

    @State private var showAddSheet = false
    @State private var editingSupplement: SupplementEntry?

    // @Query cannot filter by computed dates — use computed property
    private var todayLogs: [AdherenceLog] {
        allAdherenceLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    private var activeSupplements: [SupplementEntry] {
        supplements.filter { $0.isActive }
    }

    private var inactiveSupplements: [SupplementEntry] {
        supplements.filter { !$0.isActive }
    }

    var body: some View {
        Group {
            if supplements.isEmpty {
                emptyState
            } else {
                supplementList
            }
        }
        .navigationTitle("Health Regimen")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticService.impact(.light)
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.brand)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSupplementSheet(service: service)
        }
        .sheet(item: $editingSupplement) { supplement in
            AddSupplementSheet(editingSupplement: supplement, service: service)
        }
        .task {
            service.createPendingLogs(context: modelContext, supplements: supplements)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pill.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("No supplements yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Add supplements or medications\nto track your daily regimen.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                HapticService.impact(.light)
                showAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Supplement")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AppColors.brand)
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var supplementList: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary header
                adherenceSummary
                    .padding(.horizontal, 16)

                // Active supplements — today's doses
                if !activeSupplements.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(activeSupplements) { supplement in
                            supplementDoseCard(supplement)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Inactive supplements
                if !inactiveSupplements.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inactive")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        ForEach(inactiveSupplements) { supplement in
                            inactiveRow(supplement)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Adherence Summary

    private var adherenceSummary: some View {
        let pct = service.todayAdherencePercent(todayLogs: todayLogs)
        let taken = todayLogs.filter { $0.status == "taken" }.count
        let total = todayLogs.count
        let streak = service.currentStreak(allLogs: allAdherenceLogs)

        return VStack(spacing: 10) {
            HStack {
                Text("Today's Adherence")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(taken)/\(total) doses")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    Capsule()
                        .fill(AppColors.brand)
                        .frame(width: geo.size.width * CGFloat(pct), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.brand)
                Spacer()
                if streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("\(streak) day streak")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
        )
    }

    // MARK: - Dose Card

    private func supplementDoseCard(_ supplement: SupplementEntry) -> some View {
        let doses = todayLogs.filter { $0.supplementID == supplement.id }.sorted { $0.scheduledMinute < $1.scheduledMinute }
        let cat = supplement.resolvedCategory

        return VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: cat?.icon ?? "pill.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(cat?.color ?? AppColors.brand)
                Text(supplement.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if !supplement.dosage.isEmpty {
                    Text(supplement.dosage)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Edit
                Button {
                    HapticService.impact(.light)
                    editingSupplement = supplement
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Dose rows
            ForEach(doses, id: \.id) { log in
                doseRow(log)
            }

            if doses.isEmpty {
                Text("No doses scheduled for today")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    private func doseRow(_ log: AdherenceLog) -> some View {
        let timeStr = formatMinutes(log.scheduledMinute)

        return Button {
            HapticService.impact(.light)
            let newStatus = log.status == "taken" ? "pending" : "taken"
            service.markDose(context: modelContext, log: log, status: newStatus)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: statusIcon(log.status))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(statusColor(log.status))

                VStack(alignment: .leading, spacing: 2) {
                    Text(timeStr)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    if log.status == "taken", let at = log.takenAt {
                        Text("taken at \(formatTime(at))")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(log.status)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func inactiveRow(_ supplement: SupplementEntry) -> some View {
        HStack {
            Image(systemName: supplement.resolvedCategory?.icon ?? "pill.fill")
                .foregroundStyle(.secondary)
            Text(supplement.name)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Inactive")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground).opacity(0.6)))
    }

    // MARK: - Helpers

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "taken":   return "checkmark.circle.fill"
        case "skipped": return "xmark.circle.fill"
        default:        return "circle"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "taken":   return Color(hue: 0.38, saturation: 0.58, brightness: 0.72)
        case "skipped": return Color(hue: 0.00, saturation: 0.65, brightness: 0.80)
        default:        return .secondary
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Preview

#Preview("Supplement List") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SupplementEntry.self, AdherenceLog.self, configurations: config)
    return NavigationStack {
        SupplementListView(service: SupplementService())
    }
    .modelContainer(container)
}
