import SwiftUI
import SwiftData

struct SupplementDetailView: View {
    let supplement: SupplementEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AdherenceLog.day, order: .reverse) private var allLogs: [AdherenceLog]
    @ObservedObject var service: SupplementService

    @State private var showEditSheet = false
    @State private var showDeleteAlert = false

    private var supplementLogs: [AdherenceLog] {
        allLogs.filter { $0.supplementID == supplement.id }
    }

    private var last30Days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.reversed()
    }

    private var last30DaysLogs: [AdherenceLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return supplementLogs.filter { $0.day >= cutoff }
    }

    private var adherence7d: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = supplementLogs.filter { $0.day >= cutoff && $0.status != "pending" }
        guard !recent.isEmpty else { return 0 }
        return Double(recent.filter { $0.status == "taken" }.count) / Double(recent.count)
    }

    private var adherence30d: Double {
        let resolved = last30DaysLogs.filter { $0.status != "pending" }
        guard !resolved.isEmpty else { return 0 }
        return Double(resolved.filter { $0.status == "taken" }.count) / Double(resolved.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                adherenceGrid
                statsCard
                actionsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(supplement.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showEditSheet) {
            AddSupplementSheet(editingSupplement: supplement, service: service)
        }
        .alert("Delete Supplement?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteSupplement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the supplement and stop notifications. Adherence history will be kept.")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        let cat = supplement.resolvedCategory
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: cat?.icon ?? "pill.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(cat?.color ?? AppColors.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(supplement.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    if !supplement.dosage.isEmpty {
                        Text(supplement.dosage)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let cat {
                    Text(cat.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(cat.color)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(cat.color.opacity(0.12)))
                }
            }

            HStack(spacing: 12) {
                Label(supplement.formattedTimes.joined(separator: ", "), systemImage: "clock")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                if !supplement.isActive {
                    Text("Inactive")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
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

    // MARK: - 30-Day Adherence Grid

    private var adherenceGrid: some View {
        let logsByDay = Dictionary(grouping: last30DaysLogs) { $0.day }
        let gridDays = last30Days.enumerated().map { GridDay(offset: $0.offset, date: $0.element, logs: logsByDay[$0.element] ?? []) }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 30 Days")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(gridDays) { item in
                    gridCell(item)
                }
            }

            HStack(spacing: 16) {
                legendItem(color: Color(hue: 0.38, saturation: 0.55, brightness: 0.72), label: "Taken")
                legendItem(color: Color(hue: 0.00, saturation: 0.60, brightness: 0.80), label: "Skipped")
                legendItem(color: Color(.systemFill), label: "No data")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
        )
    }

    private struct GridDay: Identifiable {
        let offset: Int
        let date: Date
        let logs: [AdherenceLog]
        var id: Int { offset }
    }

    private func gridCell(_ item: GridDay) -> some View {
        let color = dayColor(for: item.logs)
        let dayNum = Calendar.current.component(.day, from: item.date)
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(height: 24)
            .overlay(
                Text("\(dayNum)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(color == Color(.systemFill) ? Color.secondary : Color.white.opacity(0.9))
            )
    }

    private func dayColor(for logs: [AdherenceLog]) -> Color {
        guard !logs.isEmpty else { return Color(.systemFill) }
        let allTaken = logs.allSatisfy { $0.status == "taken" }
        let anySkipped = logs.contains { $0.status == "skipped" }
        if allTaken { return Color(hue: 0.38, saturation: 0.55, brightness: 0.72) }
        if anySkipped { return Color(hue: 0.00, saturation: 0.60, brightness: 0.80) }
        return Color(.systemFill) // pending
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        let streak = service.currentStreak(allLogs: supplementLogs)

        return VStack(spacing: 14) {
            HStack {
                statItem(value: "\(Int(adherence7d * 100))%", label: "7-day")
                Divider().frame(height: 40)
                statItem(value: "\(Int(adherence30d * 100))%", label: "30-day")
                Divider().frame(height: 40)
                statItem(value: "\(streak)d", label: "Streak")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.brand)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                HapticService.impact(.light)
                showEditSheet = true
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit Supplement")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .foregroundStyle(AppColors.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.brand.opacity(0.12)))
            }

            Button {
                HapticService.impact(.light)
                showDeleteAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Supplement")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.08)))
            }
        }
    }

    private func deleteSupplement() {
        service.clearNotifications(for: supplement)
        modelContext.delete(supplement)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview("Supplement Detail") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SupplementEntry.self, AdherenceLog.self, configurations: config)
    let s = SupplementEntry(name: "Magnesium", dosage: "400mg", category: .mineral, scheduledTimes: [480, 1200])
    container.mainContext.insert(s)
    return NavigationStack {
        SupplementDetailView(supplement: s, service: SupplementService())
    }
    .modelContainer(container)
}
