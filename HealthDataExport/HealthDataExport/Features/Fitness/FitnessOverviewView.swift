import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class FitnessOverviewViewModel: ObservableObject {
    @Published private(set) var dashboard: FitnessDashboardResponse?
    @Published private(set) var recentSessions: [FitnessSessionSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let dashboardTask = FitnessAPIClient.dashboard()
        async let sessionsTask = FitnessAPIClient.recentSessions()

        do {
            let (d, s) = try await (dashboardTask, sessionsTask)
            dashboard = d
            recentSessions = s
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Turn an underlying error into a message that tells network problems apart
    /// from decoding problems, so failures aren't all masked as "check network".
    private static func describe(_ error: Error) -> String {
        switch error {
        case let urlError as URLError:
            return "网络错误：\(urlError.localizedDescription)"
        case let decodingError as DecodingError:
            return "数据解析失败：\(Self.decodingDetail(decodingError))"
        default:
            return "加载失败：\(error.localizedDescription)"
        }
    }

    private static func decodingDetail(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, ctx):
            return "缺少字段 \(key.stringValue)（\(Self.path(ctx))）"
        case let .typeMismatch(_, ctx):
            return "类型不符（\(Self.path(ctx))）"
        case let .valueNotFound(_, ctx):
            return "值为空（\(Self.path(ctx))）"
        case let .dataCorrupted(ctx):
            return ctx.debugDescription
        @unknown default:
            return "未知解析错误"
        }
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map { $0.stringValue }.joined(separator: ".")
    }

    func refresh() async {
        // SwiftUI cancels the `.refreshable` task the moment the pull gesture
        // ends. That cancellation propagates to the in-flight URLSession calls,
        // which throw `URLError.cancelled` and get mis-reported as a network
        // failure — even though the network is fine (entering the tab via
        // `.task` loads correctly). Running the load in an unstructured Task
        // detaches it from the gesture's lifetime so the requests complete.
        await Task { await load() }.value
    }
}

// MARK: - Main View

struct FitnessOverviewView: View {
    @StateObject private var vm = FitnessOverviewViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                headerSection
                    .padding(.top, 6)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)

                if let err = vm.errorMessage {
                    errorBanner(err)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                }

                if let dash = vm.dashboard {
                    statsRow(dash)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 20)

                    if !dash.strengthProgress.items.isEmpty {
                        strengthSection(dash.strengthProgress.items)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 20)
                    }

                    if dash.muscleVolume.contains(where: { $0.volumeKg > 0 }) {
                        muscleSection(dash.muscleVolume.filter { $0.volumeKg > 0 })
                            .padding(.horizontal, 18)
                            .padding(.bottom, 20)
                    }

                    if !dash.templates.isEmpty {
                        templatesSection(dash.templates)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 20)
                    }
                }

                if !vm.recentSessions.isEmpty {
                    recentSessionsSection(vm.recentSessions)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 20)
                }

                if vm.isLoading && vm.dashboard == nil {
                    ProgressView()
                        .padding(40)
                }
            }
            .padding(.bottom, 20)
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("健身")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                Text("近 30 天训练概览")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 13, weight: .semibold))
                    Text("开始训练")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(hex: "FF7847"), in: Capsule())
            }
            .buttonStyle(HapticButtonStyle())
        }
    }

    // MARK: Stats row

    private func statsRow(_ dash: FitnessDashboardResponse) -> some View {
        let totalVolume = dash.muscleVolume.reduce(0.0) { $0 + $1.volumeKg }
        let sessionCount = vm.recentSessions.count
        return HStack(spacing: 10) {
            statCard(
                value: "\(sessionCount)",
                label: "近期次数",
                symbol: "calendar.badge.checkmark",
                color: Color(hex: "FF7847")
            )
            statCard(
                value: totalVolume >= 1000 ? String(format: "%.1ft", totalVolume / 1000) : "\(Int(totalVolume))kg",
                label: "近30天总量",
                symbol: "scalemass.fill",
                color: Color(hex: "5B8AF0")
            )
            statCard(
                value: dash.strengthProgress.hasData ? "\(dash.strengthProgress.items.count)" : "—",
                label: "力量动作",
                symbol: "chart.line.uptrend.xyaxis",
                color: Color(hex: "30C46E")
            )
        }
    }

    private func statCard(value: String, label: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: Strength progress

    private func strengthSection(_ items: [StrengthProgressItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("力量进展", symbol: "chart.line.uptrend.xyaxis")

            VStack(spacing: 1) {
                ForEach(items.prefix(4)) { item in
                    strengthRow(item)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }

    private func strengthRow(_ item: StrengthProgressItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exerciseName)
                    .font(.system(size: 15, weight: .medium))
                Text("估算 1RM: \(String(format: "%.1f", item.currentEstimated1Rm)) kg")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let isUp = item.changePercent >= 0
            HStack(spacing: 3) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(format: "%+.1f%%", item.changePercent))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isUp ? Color(hex: "30C46E") : Color(hex: "F05B5B"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white)
    }

    // MARK: Muscle volume

    private func muscleSection(_ items: [MuscleVolumeItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("肌群训练量", symbol: "figure.arms.open")

            let sorted = items.sorted { $0.volumeKg > $1.volumeKg }
            let maxVol = sorted.first?.volumeKg ?? 1

            VStack(spacing: 10) {
                ForEach(sorted.prefix(5), id: \.muscleGroupId) { item in
                    muscleBar(item: item, maxVol: maxVol)
                }
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }

    private func muscleBar(item: MuscleVolumeItem, maxVol: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.muscleGroupName)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(item.volumeKg >= 1000
                     ? String(format: "%.1f t", item.volumeKg / 1000)
                     : "\(Int(item.volumeKg)) kg")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "F0F1F5"))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color(hex: "FF7847"))
                        .frame(width: geo.size.width * (item.volumeKg / maxVol), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Templates

    private func templatesSection(_ templates: [FitnessTemplateSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("训练模板", symbol: "doc.text.fill")

            VStack(spacing: 1) {
                ForEach(templates.prefix(5)) { tpl in
                    templateRow(tpl)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }

    private func templateRow(_ tpl: FitnessTemplateSummary) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: "FF7847").opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "FF7847"))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(tpl.name)
                    .font(.system(size: 15, weight: .medium))
                Text("\(tpl.exerciseCount) 个动作 · \(tpl.setCount) 组")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "C0C3CC"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    // MARK: Recent sessions

    private func recentSessionsSection(_ sessions: [FitnessSessionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("最近训练", symbol: "clock.fill")

            VStack(spacing: 8) {
                ForEach(sessions) { session in
                    sessionCard(session)
                }
            }
        }
    }

    private func sessionCard(_ session: FitnessSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(session.startedAt, style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let theme = session.trainingTheme, !theme.isEmpty {
                    Text(theme)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "FF7847"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "FF7847").opacity(0.1), in: Capsule())
                }
            }

            HStack(spacing: 0) {
                sessionMetric(
                    value: session.totalVolumeKg.map {
                        $0 >= 1000 ? String(format: "%.1ft", $0 / 1000) : "\(Int($0))kg"
                    } ?? "--",
                    label: "总量"
                )
                Divider().frame(height: 28)
                sessionMetric(value: session.totalSets.map { "\($0)" } ?? "--", label: "组数")
                Divider().frame(height: 28)
                sessionMetric(value: "\(session.totalExercises)", label: "动作")
                if let dur = session.durationSeconds {
                    Divider().frame(height: 28)
                    sessionMetric(value: formatDuration(dur), label: "时长")
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func sessionMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 13))
        }
        .foregroundStyle(Color(hex: "F05B5B"))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F05B5B").opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Section header

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "FF7847"))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
        }
    }

    // MARK: Helpers

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}
