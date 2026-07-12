import SwiftUI
import Combine

// MARK: - Session Stats Detail Sheet

@MainActor
private final class FitnessSessionStatsDetailViewModel: ObservableObject {
    let session: FitnessSessionSummary
    @Published private(set) var summary: FitnessSessionSummaryResponse?
    @Published private(set) var breakdown: FitnessSessionBreakdownResponse?
    @Published private(set) var heartRate: FitnessSessionHeartRateResponse?
    @Published private(set) var analysis: FitnessSessionAnalysisResponse?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    init(session: FitnessSessionSummary) {
        self.session = session
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let summaryResult = loadSummary(id: session.id)
        async let breakdownResult = loadBreakdown(id: session.id)
        async let heartRateResult = loadHeartRate(id: session.id)
        async let analysisResult = loadAnalysis(id: session.id)

        let results = await (summaryResult, breakdownResult, heartRateResult, analysisResult)
        summary = results.0
        breakdown = results.1
        heartRate = results.2
        analysis = results.3

        if summary == nil && breakdown == nil && heartRate == nil && analysis == nil {
            errorMessage = L10n.tr("fitness.session.load_failed")
        }
    }

    private func loadSummary(id: Int) async -> FitnessSessionSummaryResponse? {
        try? await FitnessAPIClient.sessionSummary(id: id)
    }

    private func loadBreakdown(id: Int) async -> FitnessSessionBreakdownResponse? {
        try? await FitnessAPIClient.sessionBreakdown(id: id)
    }

    private func loadHeartRate(id: Int) async -> FitnessSessionHeartRateResponse? {
        try? await FitnessAPIClient.sessionHeartRate(id: id)
    }

    private func loadAnalysis(id: Int) async -> FitnessSessionAnalysisResponse? {
        try? await FitnessAPIClient.sessionAnalysis(id: id)
    }
}

struct FitnessSessionStatsDetailSheet: View {
    let session: FitnessSessionSummary
    @StateObject private var vm: FitnessSessionStatsDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: FitnessSessionSummary) {
        self.session = session
        _vm = StateObject(wrappedValue: FitnessSessionStatsDetailViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if vm.isLoading && vm.summary == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 44)
                    } else if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "F05B5B"))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 44)
                    } else {
                        metricGrid
                        if let breakdown = vm.breakdown {
                            TrainingSplitCard(breakdown: breakdown)
                        }
                        if let heartRate = vm.heartRate {
                            HeartRateSummaryCard(heartRate: heartRate)
                        }
                        if let analysisText = vm.analysis?.analysisText ?? vm.summary?.analysis?.analysisText,
                           !analysisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            analysisCard(analysisText)
                        }
                        if let breakdown = vm.breakdown {
                            SessionExerciseSummaryCard(breakdown: breakdown)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .background(Color(hex: "F3F2F7").ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { Haptics.tap(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .frame(width: 36, height: 36)
                            .background(Color.white, in: Circle())
                    }
                }
            }
        }
        .task { await vm.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.name)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .lineLimit(2)
            Text(formatSessionDate(session.startedAt))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "9A99A4"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricGrid: some View {
        let summary = vm.summary?.session
        let duration = summary?.durationSeconds ?? session.durationSeconds
        let volume = summary?.totalVolumeKg ?? session.totalVolumeKg ?? 0
        let calories = vm.summary?.activeEnergyKcal ?? vm.summary?.totalEnergyKcal ?? summary?.activeEnergyKcal ?? summary?.totalEnergyKcal
        let avgHeartRate = vm.heartRate?.summary.avgBpm

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                SessionMetricCell(title: L10n.tr("fitness.session.stats.total_duration"), value: formatDuration(duration), isPrimary: true)
                Rectangle()
                    .fill(Color(hex: "F0EFF4"))
                    .frame(width: 1)
                SessionMetricCell(title: L10n.tr("fitness.session.stats.total_volume"), value: formatVolume(volume), isPrimary: true, isMuted: true)
            }

            Rectangle()
                .fill(Color(hex: "F0EFF4"))
                .frame(height: 1)
                .padding(.horizontal, 20)

            HStack(spacing: 0) {
                SessionMetricCell(title: L10n.tr("fitness.session.stats.calories"), value: formatCalories(calories), symbol: "flame")
                Rectangle()
                    .fill(Color(hex: "F0EFF4"))
                    .frame(width: 1)
                SessionMetricCell(title: L10n.tr("fitness.session.stats.avg_heart_rate"), value: avgHeartRate.map { "\($0) bpm" } ?? "--", symbol: "heart.fill")
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: "5A5078").opacity(0.08), radius: 26, y: 8)
    }

    private func analysisCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("fitness.session.stats.analysis"))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "5B5B61"))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SessionMetricCell: View {
    let title: String
    let value: String
    var symbol: String?
    var isPrimary = false
    var isMuted = false

    var body: some View {
        VStack(spacing: isPrimary ? 7 : 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "C9C8D2"))
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "9A99A4"))
            Text(value)
                .font(.system(size: isPrimary ? 31 : 24, weight: .heavy))
                .foregroundStyle(isMuted ? Color(hex: "B4B3BD") : Color(hex: "1C1C1E"))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: isPrimary ? 104 : 100)
        .background(Color.white)
    }
}

// MARK: - Training split & muscle load

private struct TrainingSplitCard: View {
    let breakdown: FitnessSessionBreakdownResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("fitness.session.stats.training_split"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1C22"))
                .padding(.horizontal, 4)

            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 0) {
                    SplitPercentCell(
                        title: L10n.tr("fitness.session.stats.strength"),
                        value: breakdown.trainingSplit.strengthPercent,
                        tint: Color(hex: "F5721E")
                    )

                    Rectangle()
                        .fill(Color(hex: "F0EFF4"))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)

                    SplitPercentCell(
                        title: L10n.tr("fitness.session.stats.cardio"),
                        value: breakdown.trainingSplit.cardioPercent,
                        tint: Color(hex: "F8C06A")
                    )
                    .padding(.leading, 22)
                }

                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(hex: "F5721E"))
                            .frame(width: proxy.size.width * splitFraction(breakdown.trainingSplit.strengthPercent))
                        Rectangle()
                            .fill(Color(hex: "F8C06A"))
                    }
                }
                .frame(height: 11)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color(hex: "5A5078").opacity(0.07), radius: 20, y: 6)

            if !breakdown.muscleLoadDistribution.isEmpty {
                MuscleLoadCard(items: breakdown.muscleLoadDistribution)
                    .padding(.top, 8)
            }
        }
    }

    private func splitFraction(_ value: Double) -> CGFloat {
        CGFloat(max(0, min(value, 100)) / 100)
    }
}

private struct SplitPercentCell: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%.0f%%", value))
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1C22"))
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "6A6975"))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MuscleLoadCard: View {
    let items: [FitnessBreakdownMuscleItem]

    private var visibleItems: [FitnessBreakdownMuscleItem] {
        Array(items.prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("fitness.session.stats.muscle_load"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "9A99A4"))

            HStack(alignment: .center, spacing: 18) {
                MuscleLoadDonutChart(items: visibleItems)
                    .frame(width: 120, height: 120)

                VStack(spacing: 9) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(muscleLoadColor(at: index))
                                .frame(width: 9, height: 9)
                            Text(item.muscleName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: "3A3944"))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", item.percent))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(hex: "3A3944"))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: "5A5078").opacity(0.07), radius: 20, y: 6)
    }
}

private struct MuscleLoadDonutChart: View {
    let items: [FitnessBreakdownMuscleItem]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 16)
            let total = max(items.reduce(0) { $0 + max($1.percent, 0) }, 1)
            var start = Angle.degrees(-90)

            for (index, item) in items.enumerated() {
                let degrees = max(item.percent, 0) / total * 360
                let end = start + .degrees(degrees)
                var path = Path()
                path.addArc(
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: start,
                    endAngle: end,
                    clockwise: false
                )
                context.stroke(
                    path,
                    with: .color(muscleLoadColor(at: index)),
                    style: StrokeStyle(lineWidth: 13, lineCap: .butt)
                )
                start = end
            }
        }
    }
}

/// Distinct colors assigned by position, so every muscle in the list gets its
/// own color regardless of its code (the backend returns many muscle codes and
/// hardcoding a color per code left most of them defaulting to the same gray).
private let muscleLoadPalette: [Color] = [
    Color(hex: "F5721E"), // orange
    Color(hex: "5B8DEF"), // blue
    Color(hex: "39B54A"), // green
    Color(hex: "6D6DD6"), // purple
    Color(hex: "17B5B5"), // teal
    Color(hex: "F8C06A"), // amber
    Color(hex: "EF5DA8"), // pink
    Color(hex: "4A4AC0"), // indigo
    Color(hex: "7ED957"), // light green
    Color(hex: "9A6BEF"), // violet
    Color(hex: "E85D5D"), // red
    Color(hex: "5AC8FA")  // cyan
]

private func muscleLoadColor(at index: Int) -> Color {
    muscleLoadPalette[index % muscleLoadPalette.count]
}

// MARK: - Heart rate

private struct HeartRateSummaryCard: View {
    let heartRate: FitnessSessionHeartRateResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("fitness.session.stats.heart_rate"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .padding(.horizontal, 4)
                .padding(.top, 10)

            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(heartRate.summary.avgBpm.map { "\($0)" } ?? "--")
                                .font(.system(size: 30, weight: .heavy))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Text("bpm")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                        }
                        Text(L10n.tr("fitness.session.stats.avg_heart_rate"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "9A99A4"))
                    }

                    Spacer()

                    Text(L10n.tr("fitness.session.stats.zone_label", heartRate.summary.currentZone ?? dominantZone))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color(hex: "3B82F6"))
                }

                HeartRateAreaChart(points: heartRate.timeSeries, summary: heartRate.summary)
                    .frame(height: 150)
                    .padding(.top, 14)

                HStack {
                    ForEach(0...5, id: \.self) { zone in
                        Text("Z\(zone)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(heartZoneColor(zone))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 12)

                HStack(spacing: 0) {
                    ForEach(0...5, id: \.self) { zone in
                        Rectangle()
                            .fill(heartZoneBandFill(zone))
                    }
                }
                .frame(height: 9)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.top, 5)

                HStack {
                    ForEach(0...5, id: \.self) { zone in
                        Text(heartZoneThresholdLabel(zone))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "9A99A4"))
                            .frame(maxWidth: .infinity, alignment: zone == 0 ? .leading : .center)
                    }
                    Text("176+")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "9A99A4"))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color(hex: "5A5078").opacity(0.07), radius: 20, y: 6)

            if heartRate.recovery.available, let drop = heartRate.recovery.hrDropBpm {
                Text(L10n.tr("fitness.session.stats.recovery_drop", drop))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "3FA78A"))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color(hex: "3FA78A").opacity(0.12), in: Capsule())
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }

            if !heartRate.zoneStats.isEmpty {
                HeartRateZoneDurationCard(zones: heartRate.zoneStats)
                    .padding(.top, 8)
            }
        }
    }

    private var dominantZone: Int {
        heartRate.zoneStats.max { $0.durationSeconds < $1.durationSeconds }?.zone ?? 1
    }
}

private struct HeartRateAreaChart: View {
    let points: [FitnessHeartRatePoint]
    let summary: FitnessHeartRateSummary

    private var values: [Int] {
        let series = points.compactMap(\.bpm)
        return series.isEmpty ? fallbackValues : series
    }

    private var fallbackValues: [Int] {
        guard let avg = summary.avgBpm else { return [90, 104, 112, 108, 116, 110, 118, 114] }
        return [avg - 12, avg - 3, avg + 8, avg + 2, avg + 10, avg - 4, avg + 6].map { max(40, $0) }
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .trailing) {
                VStack {
                    Text("\(displayMax)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "B4B3BD"))
                    Spacer()
                    Text("\(displayMin)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "B4B3BD"))
                        .padding(.bottom, 20)
                }

                GeometryReader { proxy in
                    let line = chartPath(in: proxy.size, closeArea: false)
                    let area = chartPath(in: proxy.size, closeArea: true)

                    area
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "F59E0B").opacity(0.18),
                                    Color(hex: "3B82F6").opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    line
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: "F59E0B"), location: 0),
                                    .init(color: Color(hex: "3B82F6"), location: 0.35),
                                    .init(color: Color(hex: "3B82F6"), location: 0.8),
                                    .init(color: Color(hex: "F59E0B"), location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                }
                .padding(.trailing, 18)
            }

            HStack {
                ForEach(timeLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "9A99A4"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var displayMax: Int {
        summary.maxBpm ?? values.max() ?? 0
    }

    private var displayMin: Int {
        summary.minBpm ?? values.min() ?? 0
    }

    private var chartMax: Int {
        max(displayMax, values.max() ?? displayMax) + 4
    }

    private var chartMin: Int {
        min(displayMin, values.min() ?? displayMin) - 4
    }

    private var timeLabels: [String] {
        let labels = points.map { compactTime($0.time) }.filter { !$0.isEmpty }
        guard labels.count >= 3 else { return ["--:--", "--:--", "--:--"] }
        return [labels.first!, labels[labels.count / 2], labels.last!]
    }

    private func chartPath(in size: CGSize, closeArea: Bool) -> Path {
        let chartPoints = chartPoints(in: size)
        guard let first = chartPoints.first else { return Path() }

        var path = Path()
        path.move(to: first)

        guard chartPoints.count > 1 else {
            if closeArea {
                path.addLine(to: CGPoint(x: first.x, y: size.height))
                path.closeSubpath()
            }
            return path
        }

        for index in 0..<(chartPoints.count - 1) {
            let current = chartPoints[index]
            let next = chartPoints[index + 1]
            let previous = index == 0 ? current : chartPoints[index - 1]
            let following = index + 2 < chartPoints.count ? chartPoints[index + 2] : next
            let tension: CGFloat = 0.24
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) * tension,
                y: current.y + (next.y - previous.y) * tension
            )
            let control2 = CGPoint(
                x: next.x - (following.x - current.x) * tension,
                y: next.y - (following.y - current.y) * tension
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }

        if closeArea {
            let last = chartPoints[chartPoints.count - 1]
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.addLine(to: CGPoint(x: first.x, y: size.height))
            path.closeSubpath()
        }
        return path
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let data = values
        let minY = chartMin
        let maxY = max(chartMax, minY + 1)
        let verticalInset: CGFloat = 8
        let bottomInset: CGFloat = 10
        let height = max(1, size.height - verticalInset - bottomInset)
        let step = data.count > 1 ? size.width / CGFloat(data.count - 1) : size.width

        return data.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let progress = CGFloat(value - minY) / CGFloat(maxY - minY)
            let y = verticalInset + (1 - progress) * height
            return CGPoint(x: x, y: y)
        }
    }

    private func compactTime(_ value: String) -> String {
        if let date = ISO8601DateFormatter().date(from: value) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if value.count >= 16 {
            let start = value.index(value.startIndex, offsetBy: 11)
            let end = value.index(start, offsetBy: 5)
            return String(value[start..<end])
        }
        return value
    }
}

private struct HeartRateZoneDurationCard: View {
    let zones: [FitnessHeartRateZoneStat]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("fitness.session.stats.zone"))
                    .frame(width: 44, alignment: .leading)
                Text(L10n.tr("fitness.session.stats.duration"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("%")
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color(hex: "A3A2AC"))
            .padding(.vertical, 12)

            ForEach(displayZones) { zone in
                HStack(spacing: 14) {
                    Text("Z\(zone.zone)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 44, alignment: .leading)

                    Text(formatDuration(zone.durationSeconds))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 96, alignment: .leading)

                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color(hex: "F2F1F6"))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(heartZoneColor(zone.zone))
                                    .frame(width: max(3, proxy.size.width * CGFloat(max(0, min(zone.percent, 100)) / 100)))
                            }
                    }
                    .frame(height: 8)

                    Text(String(format: "%.0f%%", zone.percent))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "F2F1F6"))
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: "5A5078").opacity(0.07), radius: 20, y: 6)
    }

    private var displayZones: [FitnessHeartRateZoneStat] {
        zones.sorted { $0.zone < $1.zone }
    }
}

private func heartZoneColor(_ zone: Int) -> Color {
    switch zone {
    case 0: return Color(hex: "A9C4F5")
    case 1: return Color(hex: "3B82F6")
    case 2: return Color(hex: "F5A623")
    case 3: return Color(hex: "F97316")
    case 4: return Color(hex: "EF4444")
    default: return Color(hex: "A855F7")
    }
}

private func heartZoneBandFill(_ zone: Int) -> AnyShapeStyle {
    if zone == 0 {
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color(hex: "C7D8F7"), Color(hex: "A9C4F5")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
    return AnyShapeStyle(heartZoneColor(zone))
}

private func heartZoneThresholdLabel(_ zone: Int) -> String {
    switch zone {
    case 0: return "0"
    case 1: return "98"
    case 2: return "117"
    case 3: return "137"
    case 4: return "156"
    default: return ""
    }
}

// MARK: - Exercise summary

private struct SessionExerciseSummaryCard: View {
    let breakdown: FitnessSessionBreakdownResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("fitness.session.stats.exercises"))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1C1E"))

            VStack(spacing: 14) {
                ForEach(breakdown.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(exercise.exerciseName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                                .lineLimit(1)
                            Spacer()
                            Text(L10n.tr("fitness.session.stats.set_count", exercise.setCount))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: "9A99A4"))
                        }

                        VStack(spacing: 0) {
                            ForEach(exercise.sets) { set in
                                HStack(spacing: 10) {
                                    Text("\(set.setOrder)")
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(set.isCompleted ? Color(hex: "FF7A3D") : Color(hex: "C9C8D2"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    Text(setValueText(set, trackingType: exercise.trackingType))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(set.isCompleted ? Color(hex: "3A3944") : Color(hex: "A3A2AC"))

                                    Spacer()

                                    if let rest = set.restSeconds, rest > 0 {
                                        Text(L10n.tr("fitness.session.stats.rest_duration", formatDuration(rest)))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color(hex: "A3A2AC"))
                                    }
                                }
                                .padding(.vertical, 9)

                                if set.id != exercise.sets.last?.id {
                                    Rectangle()
                                        .fill(Color(hex: "F2F1F6"))
                                        .frame(height: 1)
                                        .padding(.leading, 34)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Color(hex: "F8F8FA"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: "5A5078").opacity(0.07), radius: 20, y: 6)
    }

    private func setValueText(_ set: FitnessBreakdownSetItem, trackingType: String) -> String {
        if ExerciseTrackingDisplay.isDistanceBased(trackingType) {
            let distance = set.actualDistanceMeters.map(formatDistance) ?? "--"
            let duration = formatDuration(set.actualDurationSeconds)
            return "\(distance) x \(duration)"
        }
        if ExerciseTrackingDisplay.isTimeBased(trackingType) {
            return formatDuration(set.actualDurationSeconds)
        }
        let weight = set.actualWeightKg.map { cleanNumber($0) } ?? "--"
        let reps = set.actualReps.map { "\($0)" } ?? "--"
        return L10n.tr("fitness.session.stats.weight_reps", weight, reps)
    }

    private func cleanNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
    }
}
