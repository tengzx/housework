import SwiftUI

// MARK: - Strength Volume Analysis Card

struct StrengthVolumeAnalysisCard: View {
    let selectedRange: FitnessStrengthVolumeRange
    let period: FitnessStatsPeriod
    let response: FitnessStrengthVolumeResponse?
    let sessions: [FitnessSessionSummary]
    let checkinVolumeByDay: [Date: Double]
    let isLoading: Bool
    let isSessionsLoading: Bool
    let errorMessage: String?
    let sessionsErrorMessage: String?
    let onSelectRange: (FitnessStrengthVolumeRange) -> Void
    let onPreviousPeriod: () -> Void
    let onNextPeriod: () -> Void
    let onRetry: () -> Void
    let onRetrySessions: () -> Void
    let onSelectSession: (FitnessSessionSummary) -> Void

    private var regions: [FitnessStrengthVolumeRegion] {
        response?.regions ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("fitness.stats.analysis_title"))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Color(hex: "1C1C22"))
                    Text(L10n.tr("fitness.stats.analysis_subtitle", selectedRange.subtitle))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "9A99A4"))
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                        .frame(width: 38, height: 38)
                        .background(Color.white, in: Circle())
                        .shadow(color: Color(hex: "5A5078").opacity(0.12), radius: 14, y: 4)
                }
            }

            rangePicker
                .padding(.top, 14)

            periodSwitcher
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 16) {
                WorkoutCheckinSection(period: period, volumeByDay: checkinVolumeByDay)

                Divider()
                    .background(Color(hex: "EEEEF1"))

                HStack(spacing: 9) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "8A8994"))
                    Text(L10n.tr("fitness.stats.muscle_distribution"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: "3A3944"))
                    Spacer()
                    Text(L10n.tr("fitness.common.kilogram"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "B4B3BD"))
                }

                if let response {
                    StrengthVolumeRadialChart(regions: regions)
                        .frame(height: 300)
                        .overlay {
                            if response.totalVolumeKg <= 0 {
                                emptyState(L10n.tr("fitness.stats.empty_strength"))
                                    .offset(y: 24)
                            }
                        }
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "F05B5B"))
                        Button {
                            Haptics.tap()
                            onRetry()
                        } label: {
                            Text(L10n.tr("common.retry"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 36)
                                .background(Color(hex: "1C1C1E"), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    emptyState(L10n.tr("fitness.stats.loading"))
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: "5A5078").opacity(0.10), radius: 34, y: 10)
            .padding(.top, 16)

            sessionHistorySection
                .padding(.top, 26)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(FitnessStrengthVolumeRange.allCases) { range in
                Button {
                    onSelectRange(range)
                } label: {
                    Text(range.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selectedRange == range ? Color(hex: "26252F") : Color(hex: "A3A2AC"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            selectedRange == range ? Color.white : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .shadow(color: selectedRange == range ? .black.opacity(0.08) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(HapticButtonStyle())
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }

    private var periodSwitcher: some View {
        HStack {
            Button {
                Haptics.tap()
                onPreviousPeriod()
            } label: {
                periodArrow("chevron.left", enabled: true)
            }
            .buttonStyle(HapticButtonStyle())

            Spacer()

            Text(period.label)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "26252F"))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: period.label)

            Spacer()

            Button {
                Haptics.tap()
                onNextPeriod()
            } label: {
                periodArrow("chevron.right", enabled: period.canGoForward)
            }
            .buttonStyle(HapticButtonStyle())
            .disabled(!period.canGoForward)
        }
        .padding(.horizontal, 8)
    }

    private func periodArrow(_ symbol: String, enabled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(enabled ? Color(hex: "6D6C78") : Color(hex: "D3D2DB"))
            .frame(width: 34, height: 34)
            .background(Color.white, in: Circle())
            .shadow(color: enabled ? Color(hex: "5A5078").opacity(0.10) : .clear, radius: 8, y: 2)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(hex: "9A9AA0"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
    }

    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("fitness.stats.session_history"))
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C22"))
                Spacer()
                if isSessionsLoading {
                    ProgressView()
                        .scaleEffect(0.78)
                } else {
                    Text(selectedRange == .year ? L10n.tr("fitness.stats.latest_six") : L10n.tr("fitness.stats.all"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "A3A2AC"))
                }
            }

            if let sessionsErrorMessage {
                VStack(spacing: 10) {
                    Text(sessionsErrorMessage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "F05B5B"))
                    Button {
                        Haptics.tap()
                        onRetrySessions()
                    } label: {
                        Text(L10n.tr("common.retry"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(height: 34)
                            .padding(.horizontal, 16)
                            .background(Color(hex: "1C1C1E"), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if sessions.isEmpty {
                Text(isSessionsLoading ? L10n.tr("fitness.stats.loading_sessions") : L10n.tr("fitness.stats.empty_sessions"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "9A9AA0"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        Button {
                            onSelectSession(session)
                        } label: {
                            FitnessSessionHistoryRow(session: session)
                        }
                        .buttonStyle(HapticButtonStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Workout check-in heatmap

private struct WorkoutCheckinSection: View {
    let period: FitnessStatsPeriod
    let volumeByDay: [Date: Double]

    private var checkinCount: Int {
        volumeByDay.values.filter { $0 > 0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: "FF7A3D"))
                Text(L10n.tr("fitness.stats.checkin_title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "3A3944"))
                Spacer()
                Text(L10n.tr("fitness.stats.checkin_days", checkinCount))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "B4B3BD"))
            }

            WorkoutCheckinGrid(period: period, volumeByDay: volumeByDay)
        }
    }
}

private struct WorkoutCheckinGrid: View {
    let period: FitnessStatsPeriod
    let volumeByDay: [Date: Double]

    private let calendar = Calendar.current
    private let accent = Color(hex: "FF7A3D")
    private let emptyColor = Color(hex: "EDECF2")

    /// 每种区间的固定格子边长（周/月适中、年略小以容纳更多天）。
    private var cellSize: CGFloat {
        switch period.range {
        case .week: return 30
        case .month: return 20
        case .year: return 11
        }
    }

    private var spacing: CGFloat {
        switch period.range {
        case .week: return 8
        case .month: return 6
        case .year: return 3
        }
    }

    private var maxVolume: Double {
        max(volumeByDay.values.max() ?? 0, 1)
    }

    /// 周期内按时间顺序排列的所有日期。
    private var days: [Date] {
        let firstDay = calendar.startOfDay(for: period.startDay)
        return (0..<period.dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDay)
        }
    }

    private func color(for date: Date) -> Color {
        guard let volume = volumeByDay[date], volume > 0 else { return emptyColor }
        let intensity = 0.4 + 0.6 * min(volume / maxVolume, 1)
        return accent.opacity(intensity)
    }

    var body: some View {
        // 固定格子边长，用自适应网格铺满可用宽度并按需换行。
        let cell = cellSize
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                    .fill(color(for: day))
                    .frame(width: cell, height: cell)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FitnessSessionHistoryRow: View {
    let session: FitnessSessionSummary

    private var isExternal: Bool { session.isExternal == true }

    /// 副标题：日期 · 训练量（仅内部记录有）· 时长。
    private var subtitle: String {
        var parts = [formatSessionDate(session.startedAt)]
        if let volume = session.totalVolumeKg {
            parts.append(formatVolume(volume))
        }
        parts.append(formatDuration(session.durationSeconds))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "FFF2EA"))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: isExternal ? "figure.run" : "dumbbell")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(hex: "FF7A3D"))
                    )

                // 组数徽标只对应用内力量训练有意义；外部（Apple 健康）记录无组数。
                if let totalSets = session.totalSets {
                    Text("\(totalSets)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 23)
                        .background(Color(hex: "FF7A3D"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .offset(x: -5, y: 5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: "26252F"))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "A3A2AC"))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "C8C7D0"))
        }
        .padding(.horizontal, 16)
        .frame(height: 80)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "EEEEF1"), lineWidth: 1)
        )
    }
}

// MARK: - Radial volume chart

private struct StrengthVolumeRadialChart: View {
    let regions: [FitnessStrengthVolumeRegion]

    private var displayRegions: [FitnessStrengthVolumeRegion] {
        let fallback = [
            FitnessStrengthVolumeRegion(regionCode: "chest", regionName: L10n.tr("fitness.stats.region.chest"), volumeKg: 0),
            FitnessStrengthVolumeRegion(regionCode: "back", regionName: L10n.tr("fitness.stats.region.back"), volumeKg: 0),
            FitnessStrengthVolumeRegion(regionCode: "legs", regionName: L10n.tr("fitness.stats.region.legs"), volumeKg: 0),
            FitnessStrengthVolumeRegion(regionCode: "shoulders", regionName: L10n.tr("fitness.stats.region.shoulders"), volumeKg: 0),
            FitnessStrengthVolumeRegion(regionCode: "core", regionName: L10n.tr("fitness.stats.region.core"), volumeKg: 0),
            FitnessStrengthVolumeRegion(regionCode: "arms", regionName: L10n.tr("fitness.stats.region.arms"), volumeKg: 0)
        ]
        guard !regions.isEmpty else { return fallback }
        return fallback.map { fallbackRegion in
            regions.first(where: { $0.regionCode == fallbackRegion.regionCode }) ?? fallbackRegion
        }
    }

    private var maxVolume: Double {
        max(displayRegions.map(\.volumeKg).max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let chartSize = min(proxy.size.width * 0.62, proxy.size.height * 0.68)
            ZStack {
                ZStack {
                    ForEach(Array(displayRegions.enumerated()), id: \.element.regionCode) { index, region in
                        StrengthVolumeLayeredSector(
                            index: index,
                            count: displayRegions.count,
                            fraction: region.volumeKg / maxVolume,
                            color: regionColor(region.regionCode)
                        )
                    }

                    Circle()
                        .fill(Color.white)
                        .frame(width: chartSize * 0.24, height: chartSize * 0.24)
                }
                .frame(width: chartSize, height: chartSize)

                ForEach(Array(displayRegions.enumerated()), id: \.element.regionCode) { index, region in
                    chartLabel(for: region)
                        .position(labelPosition(for: region.regionCode, in: proxy.size))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chartLabel(for region: FitnessStrengthVolumeRegion) -> some View {
        let labelColor = region.volumeKg > 0 ? regionColor(region.regionCode) : Color(hex: "C9C8D2")
        return VStack(spacing: 2) {
            Text(formatChartVolume(region.volumeKg))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(labelColor)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(region.regionName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(labelColor)
        }
        .frame(width: 82)
    }

    private func labelPosition(for code: String, in size: CGSize) -> CGPoint {
        switch code {
        case "chest":
            return CGPoint(x: size.width * 0.50, y: 18)
        case "back":
            return CGPoint(x: size.width * 0.87, y: size.height * 0.22)
        case "legs":
            return CGPoint(x: size.width * 0.87, y: size.height * 0.78)
        case "shoulders":
            return CGPoint(x: size.width * 0.50, y: size.height - 18)
        case "core":
            return CGPoint(x: size.width * 0.13, y: size.height * 0.78)
        case "arms":
            return CGPoint(x: size.width * 0.13, y: size.height * 0.22)
        default:
            return CGPoint(x: size.width * 0.50, y: size.height * 0.50)
        }
    }
}

private struct StrengthVolumeLayeredSector: View {
    let index: Int
    let count: Int
    let fraction: Double
    let color: Color

    private let layerCount = 4

    var body: some View {
        ZStack {
            ForEach(0..<layerCount, id: \.self) { layer in
                StrengthVolumeSectorLayer(
                    index: index,
                    count: count,
                    layer: layer,
                    layerCount: layerCount
                )
                .fill(layerFill(layer))
            }
        }
    }

    private func layerFill(_ layer: Int) -> Color {
        guard fraction > 0 else {
            return Color(hex: "F1F0F6").opacity(0.72)
        }
        let activeLayers = max(1, min(layerCount, Int(ceil(fraction * Double(layerCount)))))
        guard layer < activeLayers else {
            return Color(hex: "F1F0F6").opacity(0.72)
        }
        let progress = Double(layer + 1) / Double(layerCount)
        let opacity = 0.32 + progress * 0.62
        return color.opacity(opacity)
    }
}

private struct StrengthVolumeSectorLayer: Shape {
    let index: Int
    let count: Int
    let layer: Int
    let layerCount: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let minSide = min(rect.width, rect.height)
        let innerBaseRadius = minSide * 0.13
        let outerRadius = minSide * 0.45
        let radialGap: CGFloat = 1.6
        let totalGap = radialGap * CGFloat(max(0, layerCount - 1))
        let band = (outerRadius - innerBaseRadius - totalGap) / CGFloat(layerCount)
        let innerRadius = innerBaseRadius + CGFloat(layer) * (band + radialGap)
        let endRadius = innerRadius + band
        let cornerRadius = min(2.3, band * 0.17)
        let angleInset = max(0.65, Double(cornerRadius / max(endRadius, 1)) * 180 / .pi)
        let segment = 360.0 / Double(count)
        let centerAngle = Double(index) * segment
        let half = segment * 0.485
        let start = centerAngle - half
        let end = centerAngle + half
        let outerStart = start + angleInset
        let outerEnd = end - angleInset
        let innerStart = start + angleInset
        let innerEnd = end - angleInset
        let outerSteps = max(8, Int((outerEnd - outerStart) / 5))
        let innerSteps = max(8, Int((innerEnd - innerStart) / 5))

        var path = Path()
        path.move(to: point(center: center, radius: endRadius, degrees: outerStart))
        for step in 1...outerSteps {
            let angle = outerStart + (outerEnd - outerStart) * Double(step) / Double(outerSteps)
            path.addLine(to: point(center: center, radius: endRadius, degrees: angle))
        }
        path.addQuadCurve(
            to: point(center: center, radius: endRadius - cornerRadius, degrees: end),
            control: point(center: center, radius: endRadius, degrees: end)
        )
        path.addLine(to: point(center: center, radius: innerRadius + cornerRadius, degrees: end))
        path.addQuadCurve(
            to: point(center: center, radius: innerRadius, degrees: innerEnd),
            control: point(center: center, radius: innerRadius, degrees: end)
        )
        for step in stride(from: innerSteps - 1, through: 0, by: -1) {
            let angle = innerStart + (innerEnd - innerStart) * Double(step) / Double(innerSteps)
            path.addLine(to: point(center: center, radius: innerRadius, degrees: angle))
        }
        path.addQuadCurve(
            to: point(center: center, radius: innerRadius + cornerRadius, degrees: start),
            control: point(center: center, radius: innerRadius, degrees: start)
        )
        path.addLine(to: point(center: center, radius: endRadius - cornerRadius, degrees: start))
        path.addQuadCurve(
            to: point(center: center, radius: endRadius, degrees: outerStart),
            control: point(center: center, radius: endRadius, degrees: start)
        )
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(sin(radians)),
            y: center.y - radius * CGFloat(cos(radians))
        )
    }
}

private struct StrengthVolumeMuscleRow: View {
    let muscle: FitnessStrengthVolumeMuscle
    let maxVolume: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(regionColor(muscle.regionCode))
                        .frame(width: 9, height: 9)
                    Text(muscle.muscleGroupName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "3A3944"))
                        .lineLimit(1)
                }
                Spacer()
                Text(formatVolume(muscle.volumeKg))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1C1E"))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "EFEFF4"))
                    Capsule()
                        .fill(regionColor(muscle.regionCode))
                        .frame(width: max(6, proxy.size.width * CGFloat(muscle.volumeKg / max(maxVolume, 1))))
                }
            }
            .frame(height: 7)
        }
    }
}
