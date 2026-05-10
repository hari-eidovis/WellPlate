//
//  StressActivityView.swift
//  WellPlate
//
//  Transaction-style change log of the stress score. Vertical-rail timeline
//  with one entry per `groupID`. Multi-row groups stay expandable. Routes
//  via `viewModel.usesMockData`: mock path reads
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
    private static let calibrationColor = Color(hue: 0.74, saturation: 0.45, brightness: 0.85)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroArc
                    filterChipRow
                    sectionedTimeline
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

    // MARK: - Sectioned Timeline

    @ViewBuilder
    private var sectionedTimeline: some View {
        let cal = Calendar.current
        let todayEntries = entries.filter { cal.isDateInToday($0.timestamp) }
        let yesterdayEntries = entries.filter { cal.isDateInYesterday($0.timestamp) }
        let olderEntries = entries.filter {
            !cal.isDateInToday($0.timestamp) && !cal.isDateInYesterday($0.timestamp)
        }

        VStack(alignment: .leading, spacing: 22) {
            timelineSection(title: "TODAY", items: todayEntries, showEmpty: true)
            if !yesterdayEntries.isEmpty {
                timelineSection(title: "YESTERDAY", items: yesterdayEntries, showEmpty: false)
            }
            if !olderEntries.isEmpty {
                timelineSection(title: "OLDER", items: olderEntries, showEmpty: false)
            }
        }
    }

    @ViewBuilder
    private func timelineSection(
        title: String,
        items: [any ChangeEntryDisplayable],
        showEmpty: Bool
    ) -> some View {
        let groups = groupedByEvent(items)

        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.2)
                .padding(.leading, 4)

            if groups.isEmpty && showEmpty {
                emptyStateCard
            } else {
                VStack(spacing: 0) {
                    ForEach(groups.indices, id: \.self) { i in
                        timelineEntry(
                            group: groups[i].rows,
                            isFirst: i == 0,
                            isLast: i == groups.count - 1
                        )
                    }
                }
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

    // MARK: - Timeline Entry

    @ViewBuilder
    private func timelineEntry(
        group: [any ChangeEntryDisplayable],
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        let first = group.first!
        let isAnchor = first.entryKind == .anchor && group.count == 1
        let isAllCalibration = group.allSatisfy { $0.entryKind == .calibrator }
        let isExpandable = group.count >= 2
        let isExpanded = expandedGroups.contains(first.groupID)
        let netDelta = first.totalAfter - first.totalBefore

        HStack(alignment: .top, spacing: 12) {
            timeColumn(date: first.timestamp)
                .frame(width: 50, alignment: .trailing)

            railColumn(
                dotColor: dotColor(forNetDelta: netDelta, isAnchor: isAnchor, isCalibration: isAllCalibration),
                isFirst: isFirst,
                isLast: isLast,
                isAnchor: isAnchor
            )

            VStack(alignment: .leading, spacing: 6) {
                entryHeader(
                    group: group,
                    isAnchor: isAnchor,
                    isAllCalibration: isAllCalibration,
                    isExpandable: isExpandable,
                    isExpanded: isExpanded
                )
                if let subtitle = subtitleText(for: group, isAnchor: isAnchor) {
                    Text(subtitle)
                        .font(.r(.caption, .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !isAnchor {
                    sourceFooter(group: group, isAllCalibration: isAllCalibration)
                        .padding(.top, 2)
                }

                if isExpandable && isExpanded {
                    VStack(spacing: 8) {
                        ForEach(group.indices, id: \.self) { i in
                            expandedSubrow(group[i])
                        }
                    }
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 22)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isExpandable else { return }
            HapticService.impact(.light)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                if isExpanded { expandedGroups.remove(first.groupID) }
                else { expandedGroups.insert(first.groupID) }
            }
        }
    }

    // MARK: - Time Column

    private func timeColumn(date: Date) -> some View {
        let parts = formattedTimeParts(date)
        return VStack(alignment: .trailing, spacing: 0) {
            Text(parts.time)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(parts.suffix)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 1)
    }

    // MARK: - Rail Column

    private func railColumn(
        dotColor: Color,
        isFirst: Bool,
        isLast: Bool,
        isAnchor: Bool
    ) -> some View {
        VStack(spacing: 0) {
            // Top segment (above the dot) — hidden for the first row in a section.
            Rectangle()
                .fill(railLineColor)
                .frame(width: 1.5, height: 6)
                .opacity(isFirst ? 0 : 1)

            // Dot — solid filled, with a halo of background color so it sits on top
            // of the rail line cleanly.
            ZStack {
                Circle()
                    .fill(Color(.systemGroupedBackground))
                    .frame(width: 14, height: 14)
                if isAnchor {
                    Circle()
                        .strokeBorder(dotColor, lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 9, height: 9)
                }
            }

            // Bottom segment — fills remaining row height; hidden for the last row.
            Rectangle()
                .fill(railLineColor)
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 14)
    }

    private var railLineColor: Color {
        Color(.separator).opacity(0.55)
    }

    // MARK: - Entry Header

    @ViewBuilder
    private func entryHeader(
        group: [any ChangeEntryDisplayable],
        isAnchor: Bool,
        isAllCalibration: Bool,
        isExpandable: Bool,
        isExpanded: Bool
    ) -> some View {
        let first = group.first!
        let netDelta = first.totalAfter - first.totalBefore

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(titleText(for: group, isAnchor: isAnchor))
                    .font(.r(.body, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if isAnchor {
                    Text("score \(Int(first.totalAfter.rounded()))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    deltaBadge(delta: netDelta, isCalibration: isAllCalibration)
                    Text("\(formatScore(first.totalBefore)) → \(formatScore(first.totalAfter))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if isExpandable {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Title / Subtitle Text

    private func titleText(for group: [any ChangeEntryDisplayable], isAnchor: Bool) -> String {
        let first = group.first!
        if isAnchor || group.count == 1 {
            return first.detailText
        }
        return "\(group.count) changes"
    }

    private func subtitleText(for group: [any ChangeEntryDisplayable], isAnchor: Bool) -> String? {
        if isAnchor { return nil }
        if group.count == 1 {
            // Single-row entries: detailText already used as title; no extra subtitle.
            return nil
        }
        // Multi-row group: " · "-joined detail texts.
        return group.map(\.detailText).joined(separator: " · ")
    }

    // MARK: - Source Footer

    private func sourceFooter(
        group: [any ChangeEntryDisplayable],
        isAllCalibration: Bool
    ) -> some View {
        let first = group.first!
        return HStack(spacing: 8) {
            sourceChip(source: first.source)
            if isAllCalibration {
                Text("CALIBRATION")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Self.calibrationColor)
            }
            Spacer(minLength: 0)
        }
    }

    private func sourceChip(source: StressChangeSource) -> some View {
        HStack(spacing: 4) {
            Text(source.isAuto ? "Auto" : "Manual")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Text("·")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(source.displayLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().strokeBorder(Color(.separator).opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Expanded Sub-row

    private func expandedSubrow(_ entry: any ChangeEntryDisplayable) -> some View {
        let tint = subjectTint(for: entry.entryKind)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 24, height: 24)
                Image(systemName: entry.subjectIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(entry.detailText)
                .font(.r(.caption, .semibold))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 8)
            if abs(entry.deltaPoints) > 0.001 {
                deltaBadge(delta: entry.deltaPoints, isCalibration: entry.entryKind == .calibrator, compact: true)
            }
        }
    }

    // MARK: - Delta Badge

    private func deltaBadge(delta: Double, isCalibration: Bool, compact: Bool = false) -> some View {
        let isFlat = abs(delta) < 0.05
        let isImprovement = delta < 0
        let color: Color = {
            if isCalibration { return Self.calibrationColor }
            if isFlat { return .secondary }
            return isImprovement ? .green : .red
        }()
        let magnitude = abs(delta)
        let formattedMag = String(format: "%.1f", magnitude)
        let sign: String = {
            if isFlat { return "" }
            return isImprovement ? "-" : "+"
        }()

        return HStack(spacing: 3) {
            if isCalibration {
                Text("~")
                    .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                    .baselineOffset(-1)
            } else if isFlat {
                Image(systemName: "minus")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
            } else {
                Image(systemName: isImprovement ? "arrow.down" : "arrow.up")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
            }
            Text(isFlat ? "0" : "\(sign)\(formattedMag)")
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
    }

    // MARK: - Color helpers

    private func dotColor(forNetDelta delta: Double, isAnchor: Bool, isCalibration: Bool) -> Color {
        if isAnchor { return Color(.systemGray3) }
        if isCalibration { return Self.calibrationColor }
        if delta < -0.05 { return .green }
        if delta > 0.05 { return .red }
        return Color(.systemGray3)
    }

    private func subjectTint(for kind: ChangeEntryKind) -> Color {
        switch kind {
        case .factor:               return Self.themeBlue
        case .engagementGap:        return .orange
        case .patternPenalty:       return .purple
        case .calibrator:           return Self.calibrationColor
        case .anchor:               return .gray
        case .engagementActivated:  return .orange
        }
    }

    // MARK: - Formatting helpers

    private func formattedTimeParts(_ date: Date) -> (time: String, suffix: String) {
        let f1 = DateFormatter()
        f1.dateFormat = "h:mm"
        let f2 = DateFormatter()
        f2.dateFormat = "a"
        return (f1.string(from: date), f2.string(from: date))
    }

    private func formatScore(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    // MARK: - Loading

    private func loadEntries() {
        if viewModel.usesMockData {
            let filtered = viewModel.mockChangeEntries
                .filter { matchesFilter($0) }
            entries = filtered
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

    /// Evaluates the active filter against a single entry. Used for the mock
    /// path (live path uses an equivalent SwiftData `#Predicate` in
    /// `makeDescriptor`).
    private func matchesFilter(_ entry: any ChangeEntryDisplayable) -> Bool {
        switch filter {
        case .all:
            return true
        case .calibration:
            return entry.entryKind == .calibrator
        case .auto, .logs, .mood, .symptoms, .screenTime, .food:
            guard let allowed = filter.sources else { return true }
            return allowed.contains(entry.source)
        }
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
