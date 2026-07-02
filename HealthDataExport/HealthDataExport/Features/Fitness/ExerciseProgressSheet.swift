import SwiftUI
import Combine
import UIKit
import AudioToolbox


struct ExerciseProgressTarget: Identifiable, Hashable {
    let exerciseId: Int
    let name: String
    let trackingType: String

    var id: Int { exerciseId }
}

@MainActor
private final class ExerciseProgressViewModel: ObservableObject {
    let target: ExerciseProgressTarget
    @Published private(set) var progress: ExerciseProgressResponse?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedRange: String = "30d"

    init(target: ExerciseProgressTarget) {
        self.target = target
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            progress = try await FitnessAPIClient.exerciseProgress(exerciseId: target.exerciseId, range: selectedRange)
        } catch {
            errorMessage = "历史记录加载失败"
        }
    }

    func changeRange(_ range: String) async {
        selectedRange = range
        progress = nil
        await load()
    }
}

struct ExerciseProgressSheet: View {
    let target: ExerciseProgressTarget
    @StateObject private var vm: ExerciseProgressViewModel
    @Environment(\.dismiss) private var dismiss

    init(target: ExerciseProgressTarget) {
        self.target = target
        _vm = StateObject(wrappedValue: ExerciseProgressViewModel(target: target))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rangePickerBar
                        .padding(.top, 4)

                    if vm.isLoading && vm.progress == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 42)
                    } else if let p = vm.progress, p.history.isEmpty {
                        emptyState
                    } else if let p = vm.progress {
                        summaryCard(p.summary, history: p.history, display: p.display)
                        let series = chartSeries(items: p.items, history: p.history, display: p.display)
                        if !series.isEmpty {
                            trendSection(series, display: p.display)
                        }
                        historySection(p.history, display: p.display)
                    } else if let msg = vm.errorMessage {
                        Label(msg, systemImage: "exclamationmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "F05B5B"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 42)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(Color(hex: "F7F7FA").ignoresSafeArea())
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { Haptics.tap(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await vm.load() }
    }

    // MARK: Range picker

    private var rangePickerBar: some View {
        HStack(spacing: 8) {
            ForEach([("30d", "30天"), ("90d", "90天"), ("1y", "1年")], id: \.0) { range, label in
                Button {
                    Task { await vm.changeRange(range) }
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(vm.selectedRange == range ? .white : Color(hex: "6F6F76"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            vm.selectedRange == range ? Color(hex: "FF7847") : Color(hex: "ECECEF"),
                            in: Capsule()
                        )
                }
                .buttonStyle(HapticButtonStyle())
            }
            Spacer()
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: "8E8E93"))
            Text("暂无历史记录")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text("完成几次包含该动作的训练后，这里会显示进展趋势和历史记录。")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "6F6F76"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 42)
    }

    private func effectiveKind(_ display: ExerciseProgressDisplayConfig) -> String {
        display.metricKind
    }

    private func chartSeries(
        items: [ExerciseProgressPoint],
        history: [ExerciseHistorySessionItem],
        display: ExerciseProgressDisplayConfig
    ) -> [(String, Double)] {
        items.map { ($0.date, $0.value) }
    }

    // MARK: Summary card

    private func summaryCard(_ summary: ExerciseProgressSummaryData, history: [ExerciseHistorySessionItem], display: ExerciseProgressDisplayConfig) -> some View {
        VStack(spacing: 12) {
            heroRow(summary, history: history, display: display)
            Divider()
            statsGrid(summary, display: display)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "ECECEF"), lineWidth: 1))
    }

    @ViewBuilder
    private func heroRow(_ summary: ExerciseProgressSummaryData, history: [ExerciseHistorySessionItem], display: ExerciseProgressDisplayConfig) -> some View {
        let kind = effectiveKind(display)
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heroLabel(kind))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
                heroValueView(summary, history: history, kind: kind)
            }
            Spacer()
            changeBadge(summary.changePercent, kind: kind)
        }
    }

    @ViewBuilder
    private func heroValueView(_ summary: ExerciseProgressSummaryData, history: [ExerciseHistorySessionItem], kind: String) -> some View {
        switch kind {
        case "distance":
            // Prefer latest session's total distance; fall back to summary best
            let v = history.first?.totalDistanceMeters.flatMap { $0 > 0 ? $0 : nil }
                ?? summary.bestDistanceMeters
            if let dist = v {
                Text(Self.distanceText(dist))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C1E"))
            } else {
                Text("--").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color(hex: "1C1C1E"))
            }
        case "duration":
            let v = history.first?.totalDurationSeconds.flatMap { $0 > 0 ? $0 : nil }
                ?? summary.bestDurationSeconds
            if let dur = v {
                Text(Self.durationText(dur))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C1E"))
            } else {
                Text("--").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color(hex: "1C1C1E"))
            }
        default:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(summary.latestMetricValue.map { Self.cleanNumber($0) } ?? "--")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text("kg")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
    }

    @ViewBuilder
    private func changeBadge(_ changePercent: Double?, kind: String) -> some View {
        // For cardio, the backend's changePercent is computed from estimated_1rm (= 0),
        // so it's meaningless — don't show it.
        if let pct = changePercent, kind != "distance" && kind != "duration" {
            let isUp = pct >= 0
            HStack(spacing: 4) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                Text(String(format: "%+.1f%%", pct))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(isUp ? Color(hex: "30C46E") : Color(hex: "F05B5B"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isUp ? Color(hex: "30C46E") : Color(hex: "F05B5B")).opacity(0.1),
                in: Capsule()
            )
        }
    }

    @ViewBuilder
    private func statsGrid(_ summary: ExerciseProgressSummaryData, display: ExerciseProgressDisplayConfig) -> some View {
        let cells = statCells(summary, display: display)
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { i in
                summaryStatCell(value: cells[i].0, label: cells[i].1)
                if i < cells.count - 1 {
                    Divider().frame(height: 32)
                }
            }
        }
    }

    private func statCells(_ summary: ExerciseProgressSummaryData, display: ExerciseProgressDisplayConfig) -> [(String, String)] {
        if display.usesDistance && display.usesDuration {
            return [
                (summary.bestDistanceMeters.map(Self.distanceText) ?? "--", "最远距离"),
                (summary.bestDurationSeconds.map(Self.durationText) ?? "--", "最长用时"),
                (summary.totalDistanceMeters.map(Self.distanceText) ?? "--", "累计距离"),
                ("\(summary.sessionCount)", "训练次数")
            ]
        }
        if display.usesDuration {
            return [
                (summary.bestDurationSeconds.map(Self.durationText) ?? "--", "最长时长"),
                (summary.totalDurationSeconds.map(Self.durationText) ?? "--", "累计时长"),
                ("\(summary.completedSetCount)", "完成组数"),
                ("\(summary.sessionCount)", "训练次数")
            ]
        }
        return [
            (summary.bestWeightKg.map { "\(Self.cleanNumber($0)) kg" } ?? "--", "最大重量"),
            (summary.bestReps.map { "\($0) 次" } ?? "--", "最多次数"),
            (summary.totalVolumeKg.map { $0 >= 1000 ? String(format: "%.1ft", $0/1000) : "\(Int($0))kg" } ?? "--", "总训练量"),
            ("\(summary.sessionCount)", "训练次数")
        ]
    }

    private func summaryStatCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "8E8E93"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Trend chart

    private func trendSection(_ series: [(String, Double)], display: ExerciseProgressDisplayConfig) -> some View {
        let kind = effectiveKind(display)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("进展趋势")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                if series.count > 1 {
                    Text("\(Self.shortDateStr(series.first?.0 ?? "")) – \(Self.shortDateStr(series.last?.0 ?? ""))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "8E8E93"))
                }
            }
            ProgressTrendChart(
                values: series.map(\.1),
                dates: series.map(\.0),
                metricKind: kind
            )
            .frame(height: 100)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "ECECEF"), lineWidth: 1))
    }

    // MARK: History sessions

    private func historySection(_ history: [ExerciseHistorySessionItem], display: ExerciseProgressDisplayConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("历史记录")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
            let visible = Array(history.prefix(10))
            ForEach(visible) { session in
                sessionHistoryRow(session, display: display)
                if session.id != visible.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "ECECEF"), lineWidth: 1))
    }

    private func sessionHistoryRow(_ session: ExerciseHistorySessionItem, display: ExerciseProgressDisplayConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text(Self.shortDateStr(session.startedAt ?? ""))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "FF7847"))
                    .frame(minWidth: 44, alignment: .leading)
                Text(session.sessionName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                Spacer()
                sessionMetricBadge(session, display: display)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.sets) { set in
                    sessionSetRow(set, display: display)
                }
            }
            .padding(.leading, 50)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionMetricBadge(_ session: ExerciseHistorySessionItem, display: ExerciseProgressDisplayConfig) -> some View {
        if display.usesDistance && display.usesDuration {
            if let dist = session.bestDistanceMeters, let dur = session.bestDurationSeconds {
                Text("\(Self.distanceText(dist)) · \(Self.durationText(dur))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        } else if display.usesDuration {
            if let dur = session.bestDurationSeconds {
                Text(Self.durationText(dur))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        } else {
            if let metric = session.metricValue {
                Text("1RM \(Self.cleanNumber(metric)) kg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
    }

    private func sessionSetRow(_ set: ExerciseHistorySetItem, display: ExerciseProgressDisplayConfig) -> some View {
        HStack(spacing: 6) {
            Text("组\(set.setOrder)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(set.isCompleted ? Color(hex: "FF7847") : Color(hex: "C0C3CC"))
                .frame(width: 24, alignment: .leading)

            Text(setDescription(set, display: display))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(set.isCompleted ? Color(hex: "1C1C1E") : Color(hex: "A0A0A8"))

            if display.metricKind == "estimated_1rm", let rm = set.estimated1Rm, set.isCompleted {
                Spacer()
                Text("≈\(Self.cleanNumber(rm)) kg")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
    }

    private func setDescription(_ set: ExerciseHistorySetItem, display: ExerciseProgressDisplayConfig) -> String {
        if display.usesDistance && display.usesDuration {
            let d = set.actualDistanceMeters.map(Self.distanceText) ?? "--"
            let t = set.actualDurationSeconds.map(Self.durationText) ?? "--"
            return "\(d) · \(t)"
        }
        if display.usesDuration {
            return set.actualDurationSeconds.map(Self.durationText) ?? "--"
        }
        if display.usesWeight {
            let w = set.actualWeightKg.map { "\(Self.cleanNumber($0)) kg" } ?? "--"
            let r = set.actualReps.map { "× \($0)" } ?? ""
            return "\(w) \(r)".trimmingCharacters(in: .whitespaces)
        }
        return set.actualReps.map { "\($0) 次" } ?? "--"
    }

    // MARK: Display helpers

    private func heroLabel(_ kind: String) -> String {
        switch kind {
        case "distance": return "最近一次总距离"
        case "duration": return "最近一次总时长"
        case "volume":   return "最近一次总训练量"
        case "weight":   return "最近一次最大重量"
        case "reps":     return "最近一次最多次数"
        default:         return "当前 1RM 估算"
        }
    }

    // MARK: Formatters

    static func cleanNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func durationText(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
    }

    static func shortDateStr(_ dateStr: String) -> String {
        guard !dateStr.isEmpty else { return "" }
        let parts = String(dateStr.prefix(10)).split(separator: "-")
        guard parts.count >= 3 else { return String(dateStr.prefix(10)) }
        return "\(parts[1])/\(parts[2])"
    }
}

private struct ProgressTrendChart: View {
    let values: [Double]
    let dates: [String]
    let metricKind: String

    var body: some View {
        GeometryReader { proxy in
            let rawMax = values.max() ?? 0
            let rawMin = values.min() ?? 0
            let isFlat = (rawMax - rawMin) < 0.001
            // 数据完全相同时，以实际值为中心上下各留 10% 空间，避免贴底直线
            let displayMin = isFlat ? rawMin * 0.9 : rawMin
            let displayMax = isFlat ? rawMax * 1.1 + 0.001 : rawMax
            let spread = displayMax - displayMin
            let labelH: CGFloat = 14
            let axisW: CGFloat = values.isEmpty ? 0 : axisLabelWidth
            let chartH = proxy.size.height - labelH - 6
            let chartW = proxy.size.width - axisW - 4

            ZStack(alignment: .topLeading) {
                // Y-axis labels
                VStack {
                    Text(isFlat ? formatValue(rawMax) : formatValue(displayMax))
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: "B0B0B8"))
                        .frame(width: axisW, alignment: .trailing)
                    Spacer()
                    if !isFlat {
                        Text(formatValue(displayMin))
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: "B0B0B8"))
                            .frame(width: axisW, alignment: .trailing)
                    }
                }
                .frame(height: chartH)

                // Chart area
                ZStack(alignment: .bottomLeading) {
                    // Fill
                    Path { path in
                        guard values.count >= 2 else { return }
                        for index in values.indices {
                            let x = chartW * CGFloat(index) / CGFloat(values.count - 1)
                            let ratio = CGFloat((values[index] - displayMin) / spread)
                            let y = chartH - chartH * ratio
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        path.addLine(to: CGPoint(x: chartW, y: chartH))
                        path.addLine(to: CGPoint(x: 0, y: chartH))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color(hex: "FF7847").opacity(0.15), Color(hex: "FF7847").opacity(0.01)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    // Line
                    Path { path in
                        guard !values.isEmpty else { return }
                        for index in values.indices {
                            let x = values.count == 1 ? chartW / 2 : chartW * CGFloat(index) / CGFloat(values.count - 1)
                            let ratio = CGFloat((values[index] - displayMin) / spread)
                            let y = chartH - chartH * ratio
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color(hex: "FF7847"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // Dot on last point
                    if !values.isEmpty {
                        let lastIdx = values.count - 1
                        let x = values.count == 1 ? chartW / 2 : chartW
                        let ratio = CGFloat((values[lastIdx] - displayMin) / spread)
                        let y = chartH - chartH * ratio
                        ZStack {
                            Circle().fill(Color.white).frame(width: 10, height: 10)
                            Circle().fill(Color(hex: "FF7847")).frame(width: 6, height: 6)
                        }
                        .offset(x: x - 5, y: y - 5)
                    }

                    // Date labels
                    if dates.count >= 2 {
                        HStack {
                            Text(shortDate(dates.first ?? ""))
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "B0B0B8"))
                            Spacer()
                            Text(shortDate(dates.last ?? ""))
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "B0B0B8"))
                        }
                        .offset(y: chartH + 3)
                    }
                }
                .offset(x: axisW + 4)
            }
        }
    }

    private var axisLabelWidth: CGFloat {
        metricKind == "duration" ? 38 : 32
    }

    private func formatValue(_ v: Double) -> String {
        switch metricKind {
        case "distance":
            return v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))m"
        case "duration":
            let s = Int(v)
            let m = s / 60
            if m >= 60 { return String(format: "%dh%02d", m/60, m%60) }
            return String(format: "%d:%02d", m, s % 60)
        default:
            return ExerciseProgressSheet.cleanNumber(v)
        }
    }

    private func shortDate(_ s: String) -> String {
        let p = String(s.prefix(10)).split(separator: "-")
        guard p.count >= 3 else { return "" }
        return "\(p[1])/\(p[2])"
    }
}
