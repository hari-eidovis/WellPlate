//
//  StressActivityView.swift
//  WellPlate
//
//  Transaction-style change log of the stress score. Each recompute is one
//  collapsible event card; per-row deltas live inside. Hero score-arc at top.
//  Routes via `viewModel.usesMockData`: mock path reads
//  `viewModel.mockChangeEntries`; live path runs a bounded `FetchDescriptor`.
//

import SwiftUI
import SwiftData
import Charts

struct StressActivityView: View {

    let viewModel: StressViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var entries: [any ChangeEntryDisplayable] = []
    @State private var filter: StressChangeFilter = .all
    @State private var expandedGroups: Set<UUID> = []

    init(viewModel: StressViewModel, modelContext: ModelContext) {
        self.viewModel = viewModel
        self.modelContext = modelContext
    }

    private static let themeBlue = Color(hex: "5E9FFF")

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroArc
                    filterChipRow
                    sectionedList
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .task { loadEntries() }
        .onChange(of: filter) { _ in loadEntries() }
        .onChange(of: viewModel.lastChangeEmittedAt) { _ in loadEntries() }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hero Arc

    @ViewBuilder
    private var heroArc: some View {
        let readings = viewModel.todayReadings
        let scores = readings.map(\.score)
        let firstScore = scores.first ?? viewModel.totalScore
        let currentScore = scores.last ?? viewModel.totalScore
        let peakScore = scores.max() ?? currentScore
        let lowScore = scores.min() ?? currentScore
        let netDelta = Int((currentScore - firstScore).rounded())

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY'S ARC")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.2)
                Spacer()
                if !scores.isEmpty {
                    netDeltaPill(netDelta)
                }
            }

            if scores.count < 2 {
                emptyArc(currentScore: currentScore)
            } else {
                Chart {
                    ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                        AreaMark(x: .value("t", r.timestamp), y: .value("score", r.score))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Self.themeBlue.opacity(0.30), Self.themeBlue.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("t", r.timestamp), y: .value("score", r.score))
                            .foregroundStyle(Self.themeBlue)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.4))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 84)

                HStack(spacing: 0) {
                    arcKpi(label: "Start", value: Int(firstScore))
                    Spacer()
                    arcKpi(label: "Peak",  value: Int(peakScore))
                    Spacer()
                    arcKpi(label: "Low",   value: Int(lowScore))
                    Spacer()
                    arcKpi(label: "Now",   value: Int(currentScore), highlight: true)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func emptyArc(currentScore: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(Int(currentScore))")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Current score")
                    .font(.r(.subheadline, .semibold))
                Text("Today's arc fills in as your score moves.")
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func arcKpi(label: String, value: Int, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: highlight ? 18 : 15, weight: .bold, design: .rounded))
                .foregroundColor(highlight ? Self.themeBlue : .primary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.6)
        }
    }

    private func netDeltaPill(_ netDelta: Int) -> some View {
        let isImprovement = netDelta < 0
        let isFlat = netDelta == 0
        let arrow = isFlat ? "minus" : (isImprovement ? "arrow.down" : "arrow.up")
        let color: Color = isFlat ? .secondary : (isImprovement ? .green : .red)
        let signed = isFlat ? "0" : "\(netDelta > 0 ? "+" : "")\(netDelta)"
        return HStack(spacing: 4) {
            Image(systemName: arrow)
                .font(.system(size: 10, weight: .bold))
            Text(signed)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.13)))
    }

    // MARK: - Filter Chip Row

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filterChips, id: \.0) { (filterCase, label) in
                    chip(for: filterCase, label: label)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var filterChips: [(StressChangeFilter, String)] {
        [
            (.all, "All"),
            (.auto, "Auto"),
            (.logs, "Logs"),
            (.mood, "Mood"),
            (.symptoms, "Symptoms"),
            (.screenTime, "Screen time"),
            (.food, "Food"),
            (.calibration, "Calibration"),
        ]
    }

    private func chip(for f: StressChangeFilter, label: String) -> some View {
        let isSelected = (filter == f)
        return Button {
            HapticService.impact(.light)
            filter = f
        } label: {
            Text(label)
                .font(.r(.caption, .semibold))
                .foregroundStyle(isSelected ? .white : Self.themeBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? Self.themeBlue : Self.themeBlue.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Self.themeBlue.opacity(isSelected ? 0 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sectioned List

    @ViewBuilder
    private var sectionedList: some View {
        let cal = Calendar.current
        let todayEntries = entries.filter { cal.isDateInToday($0.timestamp) }
        let yesterdayEntries = entries.filter { cal.isDateInYesterday($0.timestamp) }
        let olderEntries = entries.filter {
            !cal.isDateInToday($0.timestamp) && !cal.isDateInYesterday($0.timestamp)
        }

        VStack(alignment: .leading, spacing: 18) {
            section(title: "TODAY", items: todayEntries, showEmpty: true)
            if !yesterdayEntries.isEmpty {
                section(title: "YESTERDAY", items: yesterdayEntries, showEmpty: false)
            }
            if !olderEntries.isEmpty {
                section(title: "OLDER", items: olderEntries, showEmpty: false)
            }
        }
    }

    private func section(title: String, items: [any ChangeEntryDisplayable], showEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.2)
                .padding(.leading, 4)

            if items.isEmpty && showEmpty {
                emptyStateCard
            } else {
                eventCardList(items)
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No changes yet today.")
                .font(.r(.subheadline, .semibold))
            Text("Your stress score will log changes here as your day unfolds.")
                .font(.r(.caption, .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    @ViewBuilder
    private func eventCardList(_ items: [any ChangeEntryDisplayable]) -> some View {
        let groups = groupedByEvent(items)
        VStack(spacing: 10) {
            ForEach(groups.indices, id: \.self) { i in
                eventCard(group: groups[i].rows)
            }
        }
    }

    /// Groups an already-sorted list (timestamp DESC, sequence ASC) by groupID
    /// while preserving the outer chronological order.
    private func groupedByEvent(_ items: [any ChangeEntryDisplayable]) -> [(id: UUID, rows: [any ChangeEntryDisplayable])] {
        var seen: Set<UUID> = []
        var result: [(id: UUID, rows: [any ChangeEntryDisplayable])] = []
        for item in items {
            if seen.contains(item.groupID) { continue }
            seen.insert(item.groupID)
            let rows = items.filter { $0.groupID == item.groupID }
                .sorted { $0.sequence < $1.sequence }
            result.append((item.groupID, rows))
        }
        return result
    }

    // MARK: - Event Card Variants

    @ViewBuilder
    private func eventCard(group: [any ChangeEntryDisplayable]) -> some View {
        let first = group.first!
        let isAnchor = first.entryKind == .anchor && group.count == 1
        let isSingle = group.count == 1 && !isAnchor

        if isAnchor {
            anchorCard(first)
        } else if isSingle {
            singleRowCard(first)
        } else {
            collapsibleEventCard(group: group, isExpanded: expandedGroups.contains(first.groupID))
        }
    }

    private func anchorCard(_ entry: any ChangeEntryDisplayable) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.gray.opacity(0.13)).frame(width: 32, height: 32)
                Image(systemName: entry.subjectIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.detailText)
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                Text(formattedTime(entry.timestamp))
                    .font(.r(.caption, .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func singleRowCard(_ entry: any ChangeEntryDisplayable) -> some View {
        let tint = tintColor(for: entry.entryKind)
        return HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .fill(deltaTint(entry.deltaPoints))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: entry.subjectIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.detailText)
                        .font(.r(.subheadline, .semibold))
                        .lineLimit(1)
                    Text("\(formattedTime(entry.timestamp)) · \(entry.source.displayLabel)")
                        .font(.r(.caption, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if entry.deltaPoints != 0 {
                    deltaPill(delta: entry.deltaPoints)
                }
            }
            .padding(.vertical, 12)
            .padding(.leading, 10)
            .padding(.trailing, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func collapsibleEventCard(group: [any ChangeEntryDisplayable], isExpanded: Bool) -> some View {
        let first = group.first!
        let totalBefore = first.totalBefore
        let totalAfter = first.totalAfter
        let netDelta = totalAfter - totalBefore
        let count = group.count
        let groupID = first.groupID
        let dominant = group.max(by: { abs($0.deltaPoints) < abs($1.deltaPoints) })

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticService.impact(.light)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    if isExpanded { expandedGroups.remove(groupID) }
                    else { expandedGroups.insert(groupID) }
                }
            } label: {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(deltaTint(netDelta))
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(formattedTime(first.timestamp))
                                .font(.r(.subheadline, .semibold))
                                .foregroundStyle(.primary)
                            scoreArrowPill(before: totalBefore, after: totalAfter)
                            Spacer(minLength: 4)
                            deltaPill(delta: netDelta)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("\(count) changes")
                                .font(.r(.caption, .semibold))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .font(.r(.caption, .regular))
                                .foregroundStyle(.secondary)
                            Text(first.source.displayLabel)
                                .font(.r(.caption, .medium))
                                .foregroundStyle(.secondary)
                            if let d = dominant, d.detailText != first.source.displayLabel {
                                Text("·")
                                    .font(.r(.caption, .regular))
                                    .foregroundStyle(.secondary)
                                Text(d.detailText)
                                    .font(.r(.caption, .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().padding(.leading, 18)
                    VStack(spacing: 9) {
                        ForEach(group.indices, id: \.self) { i in
                            expandedSubrow(group[i])
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func expandedSubrow(_ entry: any ChangeEntryDisplayable) -> some View {
        let tint = tintColor(for: entry.entryKind)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 26, height: 26)
                Image(systemName: entry.subjectIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(entry.detailText)
                .font(.r(.caption, .semibold))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 8)
            if entry.deltaPoints != 0 {
                deltaPill(delta: entry.deltaPoints, compact: true)
            }
        }
    }

    // MARK: - Pills

    private func scoreArrowPill(before: Double, after: Double) -> some View {
        HStack(spacing: 4) {
            Text("\(Int(before.rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
            Text("\(Int(after.rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(.systemGray6)))
    }

    private func deltaPill(delta: Double, compact: Bool = false) -> some View {
        let isImprovement = delta < 0
        let isFlat = abs(delta) < 0.05
        let arrow = isFlat ? "minus" : (isImprovement ? "arrow.down" : "arrow.up")
        let color: Color = isFlat ? .secondary : (isImprovement ? .green : .red)
        let magnitude = abs(delta)
        let formatted: String = {
            if isFlat { return "0" }
            if magnitude >= 10 { return String(format: "%.0f", magnitude) }
            return String(format: "%.1f", magnitude)
        }()
        let sign = isFlat ? "" : (isImprovement ? "-" : "+")
        return HStack(spacing: 3) {
            Image(systemName: arrow)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            Text("\(sign)\(formatted)")
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(Capsule().fill(color.opacity(0.13)))
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
    }

    // MARK: - Helpers

    private func deltaTint(_ delta: Double) -> Color {
        if delta < -0.05 { return Color.green.opacity(0.7) }
        if delta > 0.05 { return Color.red.opacity(0.7) }
        return Color(.systemGray3)
    }

    private func tintColor(for kind: ChangeEntryKind) -> Color {
        switch kind {
        case .factor:               return Self.themeBlue
        case .engagementGap:        return .orange
        case .patternPenalty:       return .purple
        case .calibrator:           return .teal
        case .anchor:               return .gray
        case .engagementActivated:  return .orange
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    // MARK: - Loading

    private func loadEntries() {
        if viewModel.usesMockData {
            entries = viewModel.mockChangeEntries
                .sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
                    return lhs.sequence < rhs.sequence
                }
                .map { $0 as any ChangeEntryDisplayable }
            return
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let descriptor = makeDescriptor(filter: filter, retentionStart: cutoff)
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        entries = fetched.map { $0 as any ChangeEntryDisplayable }
    }

    private func makeDescriptor(filter: StressChangeFilter, retentionStart: Date) -> FetchDescriptor<StressChangeEntry> {
        var predicate = #Predicate<StressChangeEntry> { $0.timestamp >= retentionStart }
        if let allowed = filter.sources {
            let allowedRaws = allowed.map(\.rawValue)
            predicate = #Predicate<StressChangeEntry> {
                $0.timestamp >= retentionStart && allowedRaws.contains($0.sourceRaw)
            }
        } else if filter == .calibration {
            predicate = #Predicate<StressChangeEntry> {
                $0.timestamp >= retentionStart && $0.kind == "calibrator"
            }
        }
        var d = FetchDescriptor<StressChangeEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.sequence)]
        )
        d.fetchLimit = 500
        return d
    }
}
