import SwiftUI
import Combine

// MARK: - Enums

enum DashboardGranularity: String, CaseIterable {
    case day, week, month
    var tabLabel: String {
        switch self {
        case .day: return SharedL10n.tr("time.dashboard.tab.day")
        case .week: return SharedL10n.tr("time.dashboard.tab.week")
        case .month: return SharedL10n.tr("time.dashboard.tab.month")
        }
    }
}

enum LoadKind: String, CaseIterable, Identifiable {
    case obligation = "OBLIGATION"
    case proactive = "PROACTIVE"
    case recovery = "RECOVERY"
    case distraction = "DISTRACTION"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .obligation: return SharedL10n.tr("time.dashboard.load_kind.obligation")
        case .proactive: return SharedL10n.tr("time.dashboard.load_kind.proactive")
        case .recovery: return SharedL10n.tr("time.dashboard.load_kind.recovery")
        case .distraction: return SharedL10n.tr("time.dashboard.load_kind.distraction")
        }
    }

    var color: Color {
        switch self {
        case .obligation: return Color(hex: "6B7A99")
        case .proactive: return Color(hex: "E8743B")
        case .recovery: return Color(hex: "3FA78A")
        case .distraction: return Color(hex: "C9485B")
        }
    }

    static func from(_ rawValue: String) -> LoadKind? {
        LoadKind(rawValue: rawValue.uppercased())
    }
}

// MARK: - API Response Models

struct DashboardOverviewResponse: Decodable {
    var granularity: String
    var anchorDate: String
    var range: DashboardDateRange
    var headline: DashboardHeadline
    var healthScore: DashboardHealthScore
    var cards: [DashboardCard]
}

struct DashboardDateRange: Decodable {
    var start: String
    var end: String
    var label: String
}

struct DashboardHeadline: Decodable {
    var title: String
    var summary: String
    var badge: String
    var trend: String?
}

struct DashboardHealthScore: Decodable {
    var score: Int
    var label: String
    var delta: Int?
}

struct DashboardCard: Decodable, Identifiable {
    var loadKind: String
    var label: String
    var percent: Int
    var totalMinutes: Int
    var totalLabel: String
    var changePercent: Int
    var changeLabel: String
    var tone: String?
    var target: String?
    var sparkline: [Int]

    var id: String { loadKind }
}

struct DashboardCompositionResponse: Decodable {
    var loadKind: String
    var loadKindLabel: String
    var granularity: String
    var anchorDate: String
    var range: DashboardDateRange
    var summary: CompositionSummary
    var stackedBar: [StackedBarItem]
    var categories: [CompositionCategory]
}

struct CompositionSummary: Decodable {
    var totalMinutes: Int
    var totalLabel: String
    var percentOfAllTracked: Int
    var deltaPercent: Int
    var deltaLabel: String
    var status: String?
}

struct StackedBarItem: Decodable {
    var categoryId: String
    var categoryName: String
    var color: String
    var minutes: Int
    var percent: Int
}

struct CompositionCategory: Decodable {
    var categoryId: String
    var categoryName: String
    var color: String
    var minutes: Int
    var durationLabel: String
    var percent: Int
    var subtypes: [CompositionSubtype]
}

struct CompositionSubtype: Decodable {
    var typeId: String
    var typeName: String
    var minutes: Int
    var durationLabel: String
}

struct DashboardTrendResponse: Decodable {
    var loadKind: String
    var loadKindLabel: String
    var granularity: String
    var anchorDate: String
    var window: Int
    var averageMinutes: Int
    var points: [TrendPoint]
}

struct TrendPoint: Decodable {
    var label: String
    var start: String
    var end: String
    var totalMinutes: Int
}

// MARK: - Daily Review Models

struct DailyReviewResponse: Decodable, Identifiable {
    var id: Int
    var userId: Int
    var reviewDate: String
    var reviewText: String
    var modelName: String?
}

// MARK: - Mobile App Usage Models

struct MobileAppSummaryResponse: Decodable {
    var granularity: String
    var anchorDate: String
    var range: DashboardDateRange
    var userId: Int
    var totalDurationSeconds: Int
    var totalDurationLabel: String
    var totalOpenCount: Int
    var totalOpenCountLabel: String
    var comparison: MobileAppComparison
    var topApps: [MobileTopApp]
}

struct MobileAppComparison: Decodable {
    var previousPeriodLabel: String
    var deltaDurationSeconds: Int
    var deltaDurationDisplay: String
    var durationTrend: String
    var durationComparisonText: String
}

struct MobileTopApp: Decodable, Identifiable {
    var rank: Int
    var appName: String
    var bundleId: String?
    var openCount: Int
    var openCountLabel: String
    var durationSeconds: Int
    var durationLabel: String
    var id: Int { rank }
}

// MARK: - API

private enum TimeDashboardAPI {
    private static let base = TimeCalendarAPI.baseURL

    static func overview(granularity: DashboardGranularity, anchorDate: Date) async throws -> DashboardOverviewResponse {
        try await get(DashboardOverviewResponse.self, path: "time-dashboard/overview", params: [
            "granularity": granularity.rawValue,
            "anchorDate": anchorDate.dashboardDateString
        ])
    }

    static func composition(loadKind: LoadKind, granularity: DashboardGranularity, anchorDate: Date) async throws -> DashboardCompositionResponse {
        try await get(DashboardCompositionResponse.self, path: "time-load-report/composition", params: [
            "loadKind": loadKind.rawValue,
            "granularity": granularity.rawValue,
            "anchorDate": anchorDate.dashboardDateString
        ])
    }

    static func trend(loadKind: LoadKind, granularity: DashboardGranularity, anchorDate: Date) async throws -> DashboardTrendResponse {
        try await get(DashboardTrendResponse.self, path: "time-load-report/trend", params: [
            "loadKind": loadKind.rawValue,
            "granularity": granularity.rawValue,
            "anchorDate": anchorDate.dashboardDateString
        ])
    }

    static func mobileAppSummary(granularity: DashboardGranularity, anchorDate: Date) async throws -> MobileAppSummaryResponse {
        try await get(MobileAppSummaryResponse.self, path: "mobile/app-sessions/summary", params: [
            "granularity": granularity.rawValue,
            "anchorDate": anchorDate.dashboardDateString
        ])
    }

    static func dailyReviews(from: String, to: String) async throws -> [DailyReviewResponse] {
        try await get([DailyReviewResponse].self, path: "daily-reviews", params: [
            "from": from,
            "to": to
        ])
    }

    private static func get<T: Decodable>(_ type: T.Type, path: String, params: [String: String]) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = params.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await HTTPClient.shared.decode(T.self, url: components.url!, method: .get)
    }
}

private extension Date {
    var dashboardDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: self)
    }
}

// MARK: - ViewModel

@MainActor
final class TimeDashboardViewModel: ObservableObject {
    @Published var granularity: DashboardGranularity = .week
    @Published var anchorDate: Date = .now
    @Published var overview: DashboardOverviewResponse?
    @Published var compositionMap: [String: DashboardCompositionResponse] = [:]
    @Published var trendMap: [String: DashboardTrendResponse] = [:]
    @Published var selectedCard: DashboardCard?
    @Published var mobileAppSummary: MobileAppSummaryResponse?
    @Published var isLoadingOverview = false
    @Published var isLoadingComposition = false
    @Published var isLoadingTrend = false
    @Published var errorMessage = ""

    @Published var showReviewSheet = false
    @Published var dailyReviews: [DailyReviewResponse] = []
    @Published var isLoadingReviews = false
    @Published var reviewErrorMessage = ""

    var taskID: String { "\(granularity.rawValue)-\(anchorDate.dashboardDateString)" }

    var selectedComposition: DashboardCompositionResponse? {
        guard let kind = selectedCard?.loadKind else { return nil }
        return compositionMap[kind]
    }

    var selectedTrend: DashboardTrendResponse? {
        guard let kind = selectedCard?.loadKind else { return nil }
        return trendMap[kind]
    }

    var rangeLabel: String {
        overview?.range.label ?? computedRangeLabel
    }

    var topSubtitle: String {
        let cal = Calendar(identifier: .gregorian)
        switch granularity {
        case .day:
            let fmt = DateFormatter()
            fmt.locale = L10n.locale
            fmt.setLocalizedDateFormatFromTemplate("M d EEEE")
            return fmt.string(from: anchorDate)
        case .week:
            let weekday = cal.component(.weekday, from: anchorDate)
            let daysToMon = (weekday - 2 + 7) % 7
            let monday = cal.date(byAdding: .day, value: -daysToMon, to: anchorDate)!
            let month = cal.component(.month, from: monday)
            let day = cal.component(.day, from: monday)
            let weekOfMonth = (day - 1) / 7 + 1
            return SharedL10n.tr("time.dashboard.week_of_month", month, weekOfMonth)
        case .month:
            let fmt = DateFormatter()
            fmt.locale = L10n.locale
            fmt.setLocalizedDateFormatFromTemplate("yMMMM")
            return fmt.string(from: anchorDate)
        }
    }

    private var computedRangeLabel: String {
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.locale = L10n.locale
        switch granularity {
        case .day:
            fmt.setLocalizedDateFormatFromTemplate("Md")
            return fmt.string(from: anchorDate)
        case .week:
            let weekday = cal.component(.weekday, from: anchorDate)
            let daysToMon = (weekday - 2 + 7) % 7
            let monday = cal.date(byAdding: .day, value: -daysToMon, to: anchorDate)!
            let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
            fmt.setLocalizedDateFormatFromTemplate("Md")
            return SharedL10n.tr("time.dashboard.range_between", fmt.string(from: monday), fmt.string(from: sunday))
        case .month:
            fmt.setLocalizedDateFormatFromTemplate("yMMMM")
            return fmt.string(from: anchorDate)
        }
    }

    func load() async {
        overview = nil
        compositionMap = [:]
        trendMap = [:]
        mobileAppSummary = nil
        dailyReviews = []
        reviewErrorMessage = ""
        isLoadingOverview = true
        errorMessage = ""
        defer { isLoadingOverview = false }
        async let overviewResult = TimeDashboardAPI.overview(granularity: granularity, anchorDate: anchorDate)
        async let mobileResult = TimeDashboardAPI.mobileAppSummary(granularity: granularity, anchorDate: anchorDate)
        do {
            overview = try await overviewResult
        } catch {
            errorMessage = error.localizedDescription
        }
        mobileAppSummary = try? await mobileResult
        // 每日复盘仅在“日”维度提供；预取以决定卡片是否可点击。
        if granularity == .day {
            await loadDailyReviews()
        }
    }

    /// 存在复盘记录时，顶部“今日方向”卡片才可点击查看。
    var hasDailyReview: Bool {
        granularity == .day && !dailyReviews.isEmpty
    }

    func loadComposition(for card: DashboardCard) async {
        guard let kind = LoadKind.from(card.loadKind) else { return }
        isLoadingComposition = true
        defer { isLoadingComposition = false }
        do {
            let result = try await TimeDashboardAPI.composition(loadKind: kind, granularity: granularity, anchorDate: anchorDate)
            compositionMap[card.loadKind] = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTrend(for card: DashboardCard) async {
        guard let kind = LoadKind.from(card.loadKind) else { return }
        isLoadingTrend = true
        defer { isLoadingTrend = false }
        do {
            let result = try await TimeDashboardAPI.trend(loadKind: kind, granularity: granularity, anchorDate: anchorDate)
            trendMap[card.loadKind] = result
        } catch {
            // Trend is supplementary; silently ignore errors
        }
    }

    /// 复盘弹框标题（仅“日”维度提供每日复盘）。
    var reviewSheetTitle: String { SharedL10n.tr("time.dashboard.review.today") }

    func loadDailyReviews() async {
        // 每日复盘按日期查询，from/to 需为 yyyy-MM-dd（服务端 range 是带时区的 ISO datetime，不能直接用）。
        let day = anchorDate.dashboardDateString
        isLoadingReviews = true
        reviewErrorMessage = ""
        defer { isLoadingReviews = false }
        do {
            let result = try await TimeDashboardAPI.dailyReviews(from: day, to: day)
            dailyReviews = result
        } catch {
            dailyReviews = []
            reviewErrorMessage = error.localizedDescription
        }
    }

    func navigate(by amount: Int) {
        let cal = Calendar(identifier: .gregorian)
        switch granularity {
        case .day:
            anchorDate = cal.date(byAdding: .day, value: amount, to: anchorDate)!
        case .week:
            anchorDate = cal.date(byAdding: .weekOfYear, value: amount, to: anchorDate)!
        case .month:
            anchorDate = cal.date(byAdding: .month, value: amount, to: anchorDate)!
        }
    }
}

// MARK: - Main View

struct TimeDashboardView: View {
    @ObservedObject var viewModel: TimeDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 14)

                granularityPicker
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                dateNavigatorBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)

                if let overview = viewModel.overview {
                    VerdictCardView(overview: overview, showReviewHint: viewModel.hasDailyReview)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard viewModel.hasDailyReview else { return }
                            Haptics.tap()
                            viewModel.showReviewSheet = true
                        }

                    HStack {
                        Text(SharedL10n.tr("time.dashboard.section.load_cards"))
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color(hex: "1C1B1A"))
                        Spacer()
                        Text(SharedL10n.tr("time.dashboard.section.load_cards_hint"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "A6A29C"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(overview.cards) { card in
                            LoadCardView(card: card)
                                .onTapGesture { Haptics.tap(); viewModel.selectedCard = card }
                        }
                    }
                    .padding(.horizontal, 16)

                    if let summary = viewModel.mobileAppSummary {
                        HStack {
                            Text(SharedL10n.tr("time.dashboard.section.mobile_usage"))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Color(hex: "1C1B1A"))
                            Spacer()
                            Text(SharedL10n.tr("time.dashboard.section.top_apps"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "A6A29C"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, 12)

                        MobileUsageSectionView(summary: summary, granularity: viewModel.granularity)
                            .padding(.horizontal, 16)
                    }

                } else if viewModel.isLoadingOverview {
                    ProgressView()
                        .padding(.top, 60)
                } else if !viewModel.errorMessage.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(viewModel.errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                    .padding(.horizontal, 32)
                }
            }
            .padding(.bottom, 32)
        }
        .collapsibleTabScroll()
        .background(Color(hex: "F5F6F8").ignoresSafeArea())
        .tint(Color(hex: "0A84FF"))
        .task(id: viewModel.taskID) {
            await viewModel.load()
        }
        .sheet(item: $viewModel.selectedCard) { card in
            CompositionSheetView(
                card: card,
                composition: viewModel.selectedComposition,
                isLoading: viewModel.isLoadingComposition,
                trend: viewModel.selectedTrend,
                isLoadingTrend: viewModel.isLoadingTrend
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .task {
                async let comp: () = viewModel.loadComposition(for: card)
                async let trnd: () = viewModel.loadTrend(for: card)
                _ = await (comp, trnd)
            }
        }
        .sheet(isPresented: $viewModel.showReviewSheet) {
            DailyReviewSheetView(
                title: viewModel.reviewSheetTitle,
                reviews: viewModel.dailyReviews,
                isLoading: viewModel.isLoadingReviews,
                errorMessage: viewModel.reviewErrorMessage
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(SharedL10n.tr("time.dashboard.title"))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1B1A"))
            Spacer()
            Text(viewModel.topSubtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "A6A29C"))
        }
    }

    private var granularityPicker: some View {
        HStack(spacing: 2) {
            ForEach(DashboardGranularity.allCases, id: \.self) { g in
                Button {
                    viewModel.granularity = g
                } label: {
                    Text(g.tabLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(viewModel.granularity == g ? Color(hex: "1C1B1A") : Color(hex: "6B6864"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(viewModel.granularity == g ? Color.white : Color.clear)
                                .shadow(color: .black.opacity(viewModel.granularity == g ? 0.05 : 0), radius: 8, x: 0, y: 1)
                        )
                        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: viewModel.granularity)
                }
                .buttonStyle(HapticButtonStyle())
            }
        }
        .padding(4)
        .background(Color(hex: "ECEDF0"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dateNavigatorBar: some View {
        HStack {
            Button { viewModel.navigate(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "6B6864"))
                    .frame(width: 30, height: 30)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color(hex: "E4E4E9"), lineWidth: 1))
            }
            .buttonStyle(HapticButtonStyle())

            Spacer()

            Text(viewModel.rangeLabel)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "1C1B1A"))

            Spacer()

            Button { viewModel.navigate(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "6B6864"))
                    .frame(width: 30, height: 30)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color(hex: "E4E4E9"), lineWidth: 1))
            }
            .buttonStyle(HapticButtonStyle())
        }
    }
}

// MARK: - Verdict Card

private struct VerdictCardView: View {
    let overview: DashboardOverviewResponse
    var showReviewHint: Bool = false

    private var eyebrow: String {
        switch overview.granularity {
        case "day": return SharedL10n.tr("time.dashboard.headline.day")
        case "month": return SharedL10n.tr("time.dashboard.headline.month")
        default: return SharedL10n.tr("time.dashboard.headline.week")
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Color(hex: "A6A29C"))
                    .padding(.bottom, 10)

                Text(overview.headline.title)
                    .font(.system(size: 22, weight: .heavy))
                    .lineSpacing(3)
                    .foregroundStyle(Color(hex: "1C1B1A"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)

                Text(overview.headline.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "6B6864"))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                HStack(spacing: 8) {
                    trendBadge
                    if showReviewHint {
                        Text(SharedL10n.tr("time.dashboard.review.view"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "A6A29C"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 110)

            HealthRingView(score: overview.healthScore)
                .frame(width: 88, height: 88)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(0.05), radius: 24, x: 0, y: 8)
    }

    private var trendBadge: some View {
        let isBetter = overview.headline.trend == "better"
        return HStack(spacing: 4) {
            if isBetter {
                Text("▲")
            }
            Text(overview.headline.badge)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color(hex: "3FA78A"))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: "3FA78A").opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Health Ring

private struct HealthRingView: View {
    let score: DashboardHealthScore

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "EFEBE2"), lineWidth: 10)

            Circle()
                .trim(from: 0, to: min(CGFloat(score.score) / 100.0, 1.0))
                .stroke(
                    Color(hex: "E8743B"),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: score.score)

            VStack(spacing: 2) {
                Text("\(score.score)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1B1A"))
                Text(score.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: "A6A29C"))
            }
        }
    }
}

// MARK: - Load Card

private struct LoadCardView: View {
    let card: DashboardCard

    private var loadColor: Color {
        LoadKind.from(card.loadKind)?.color ?? Color(hex: "8A8F9C")
    }

    private var goalDisplay: (label: String, bg: Color, fg: Color) {
        switch card.target?.lowercased() {
        case "maximize", "increase", "more", "越多越好":
            return (SharedL10n.tr("time.dashboard.goal.maximize"), Color(hex: "3FA78A").opacity(0.1), Color(hex: "3FA78A"))
        case "minimize", "decrease", "less", "越少越好":
            return (SharedL10n.tr("time.dashboard.goal.minimize"), Color(hex: "C9485B").opacity(0.1), Color(hex: "C9485B"))
        default:
            return (SharedL10n.tr("time.dashboard.goal.maintain"), Color(hex: "F0ECE3"), Color(hex: "A6A29C"))
        }
    }

    private var deltaColor: Color {
        switch card.tone?.lowercased() {
        case "good": return Color(hex: "3FA78A")
        case "warn", "bad": return Color(hex: "C9485B")
        default: return Color(hex: "A6A29C")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(loadColor)
                        .frame(width: 9, height: 9)
                    Text(card.label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1B1A"))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                let goal = goalDisplay
                Text(goal.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(goal.fg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(goal.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.bottom, 6)

            Text("\(card.percent)%")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(loadColor)
                .padding(.bottom, 3)

            Text(card.totalLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "A6A29C"))
                .padding(.bottom, 8)

            Text(card.changeLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(deltaColor)
                .padding(.bottom, 10)

            SparklineView(values: card.sparkline, color: loadColor)
                .frame(height: 30)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(0.05), radius: 24, x: 0, y: 8)
    }
}

// MARK: - Sparkline

private struct SparklineView: View {
    let values: [Int]
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                let isLast = idx == values.count - 1
                let fraction = max(CGFloat(value) / 100.0, 0.02)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color.opacity(isLast ? 1.0 : 0.35))
                            .frame(height: geo.size.height * fraction)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Composition Sheet

struct CompositionSheetView: View {
    let card: DashboardCard
    let composition: DashboardCompositionResponse?
    let isLoading: Bool
    let trend: DashboardTrendResponse?
    let isLoadingTrend: Bool

    private var loadColor: Color {
        LoadKind.from(card.loadKind)?.color ?? Color(hex: "8A8F9C")
    }

    private var goalDisplay: (label: String, bg: Color, fg: Color) {
        switch card.target?.lowercased() {
        case "maximize", "increase", "more", "越多越好":
            return (SharedL10n.tr("time.dashboard.goal.maximize"), Color(hex: "3FA78A").opacity(0.1), Color(hex: "3FA78A"))
        case "minimize", "decrease", "less", "越少越好":
            return (SharedL10n.tr("time.dashboard.goal.minimize"), Color(hex: "C9485B").opacity(0.1), Color(hex: "C9485B"))
        default:
            return (SharedL10n.tr("time.dashboard.goal.maintain"), Color(hex: "F0ECE3"), Color(hex: "A6A29C"))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sheetHeader
                    .padding(.bottom, 4)

                if let comp = composition {
                    metaText(comp)
                        .padding(.bottom, 18)

                    if !comp.stackedBar.isEmpty {
                        StackedBarView(items: comp.stackedBar)
                            .frame(height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.bottom, 18)
                    }

                    Text(SharedL10n.tr("time.dashboard.composition.title"))
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color(hex: "A6A29C"))
                        .padding(.bottom, 6)

                    ForEach(comp.categories, id: \.categoryId) { cat in
                        CategoryRowView(category: cat)
                    }

                    // Trend section
                    if let t = trend {
                        TrendSectionView(trend: t, color: loadColor)
                    } else if isLoadingTrend {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.top, 28)
                            Spacer()
                        }
                    }

                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .background(Color.white)
    }

    private var sheetHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(loadColor)
                .frame(width: 11, height: 11)
            Text(card.label)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color(hex: "1C1B1A"))
            Spacer()
            let goal = goalDisplay
            Text(goal.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(goal.fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(goal.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func metaText(_ comp: DashboardCompositionResponse) -> some View {
        (
            Text(SharedL10n.tr("time.dashboard.period.current_prefix")).foregroundStyle(Color(hex: "6B6864"))
            + Text(comp.summary.totalLabel).fontWeight(.bold).foregroundStyle(Color(hex: "1C1B1A"))
            + Text(SharedL10n.tr("time.dashboard.period.of_total_prefix")).foregroundStyle(Color(hex: "6B6864"))
            + Text("\(comp.summary.percentOfAllTracked)%").fontWeight(.bold).foregroundStyle(Color(hex: "1C1B1A"))
            + Text(SharedL10n.tr("time.dashboard.period.compare_prefix")).foregroundStyle(Color(hex: "6B6864"))
            + Text(comp.summary.deltaLabel).fontWeight(.bold).foregroundStyle(Color(hex: "1C1B1A"))
        )
        .font(.system(size: 14))
    }
}

// MARK: - Daily Review Sheet

struct DailyReviewSheetView: View {
    let title: String
    let reviews: [DailyReviewResponse]
    let isLoading: Bool
    let errorMessage: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "E8743B"))
                    Text(title)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color(hex: "1C1B1A"))
                    Spacer()
                }
                .padding(.bottom, 18)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if !reviews.isEmpty {
                    ForEach(reviews) { review in
                        DailyReviewRowView(review: review, showDate: reviews.count > 1)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .background(Color.white)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: errorMessage.isEmpty ? "text.badge.checkmark" : "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: "C6C2BB"))
            Text(errorMessage.isEmpty ? SharedL10n.tr("time.dashboard.review.empty") : errorMessage)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "A6A29C"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 24)
    }
}

private struct DailyReviewRowView: View {
    let review: DailyReviewResponse
    let showDate: Bool

    private var dateLabel: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: review.reviewDate) else { return review.reviewDate }
        let fmt = DateFormatter()
        fmt.locale = L10n.locale
        fmt.setLocalizedDateFormatFromTemplate("M d EEEE")
        return fmt.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDate {
                Text(dateLabel)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color(hex: "A6A29C"))
                    .padding(.bottom, 8)
            }

            MarkdownContentView(markdown: review.reviewText)

            if let model = review.modelName, !model.isEmpty {
                Text(model)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "C6C2BB"))
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "F7F5F0"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.bottom, 12)
    }
}

// MARK: - Lightweight Markdown Renderer

/// 复盘正文以 Markdown 存储（# 标题、## 小节、- 列表），此处按块渲染，
/// 而不是直接 Text 显示原始 # 符号。行内 **加粗**/*斜体* 交给系统解析。
private struct MarkdownContentView: View {
    let markdown: String

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case paragraph(text: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(inline(text))
                        .font(.system(size: level == 1 ? 18 : (level == 2 ? 16 : 14), weight: .heavy))
                        .foregroundStyle(Color(hex: "1C1B1A"))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, level <= 2 ? 6 : 0)
                case let .bullet(text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "A6A29C"))
                        Text(inline(text))
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .foregroundStyle(Color(hex: "3A3936"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .paragraph(text):
                    Text(inline(text))
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .foregroundStyle(Color(hex: "3A3936"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("### ") {
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.bullet(text: String(line.dropFirst(2))))
            } else {
                result.append(.paragraph(text: line))
            }
        }
        return result
    }

    private func inline(_ raw: String) -> AttributedString {
        (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }
}

// MARK: - Stacked Bar

private struct StackedBarView: View {
    let items: [StackedBarItem]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(items, id: \.categoryId) { item in
                    Color(hex: item.color)
                        .frame(width: geo.size.width * CGFloat(item.percent) / 100.0)
                }
            }
        }
    }
}

// MARK: - Category Row

private struct CategoryRowView: View {
    let category: CompositionCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: category.color))
                    .frame(width: 10, height: 10)
                Text(category.categoryName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1B1A"))
                Spacer()
                Text(category.durationLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "6B6864"))
                Text("\(category.percent)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "A6A29C"))
                    .frame(width: 40, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: "F0ECE3"))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: category.color))
                        .frame(width: geo.size.width * CGFloat(category.percent) / 100.0)
                }
            }
            .frame(height: 6)
            .padding(.top, 9)

            if !category.subtypes.isEmpty {
                DashboardFlowLayout(spacing: 6) {
                    ForEach(category.subtypes, id: \.typeId) { sub in
                        HStack(spacing: 0) {
                            Text(sub.typeName)
                                .foregroundStyle(Color(hex: "6B6864"))
                            Text(" \(sub.durationLabel)")
                                .foregroundStyle(Color(hex: "A6A29C"))
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(hex: "F4F1EA"))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 19)
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "E4E4E9"))
                .frame(height: 1)
        }
    }
}

// MARK: - Trend Section

private struct TrendSectionView: View {
    let trend: DashboardTrendResponse
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(hex: "E4E4E9"))
                .frame(height: 1)
                .padding(.top, 20)

            HStack(alignment: .firstTextBaseline) {
                Text(SharedL10n.tr("time.dashboard.trend.title"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color(hex: "A6A29C"))
                Spacer()
                if let last = trend.points.last, !trend.points.isEmpty {
                    (Text(SharedL10n.tr("time.dashboard.period.current_prefix")).foregroundStyle(Color(hex: "A6A29C"))
                     + Text(minutesLabel(last.totalMinutes)).foregroundStyle(color).fontWeight(.bold)
                     + Text(SharedL10n.tr("time.dashboard.trend.average", minutesLabel(trend.averageMinutes))).foregroundStyle(Color(hex: "A6A29C")))
                        .font(.system(size: 12))
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 14)

            if !trend.points.isEmpty {
                TrendBarChart(
                    points: trend.points,
                    averageMinutes: trend.averageMinutes,
                    color: color
                )
            }
        }
    }

    private func minutesLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h\(m)m"
    }
}

private struct TrendBarChart: View {
    let points: [TrendPoint]
    let averageMinutes: Int
    let color: Color

    private var maxMinutes: Int {
        max(points.map(\.totalMinutes).max() ?? 1, averageMinutes, 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                // Bars + average line via Canvas
                Canvas { ctx, size in
                    let count = points.count
                    guard count > 0 else { return }
                    let gap: CGFloat = points.count > 8 ? 5 : 7
                    let barW = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                    let maxH = CGFloat(maxMinutes)

                    // Dashed average line
                    let avgFrac = CGFloat(averageMinutes) / maxH
                    let avgY = size.height * (1 - avgFrac)
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: 0, y: avgY))
                    linePath.addLine(to: CGPoint(x: size.width, y: avgY))
                    ctx.stroke(
                        linePath,
                        with: .color(Color(hex: "A6A29C").opacity(0.5)),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )

                    // Bars
                    for (i, point) in points.enumerated() {
                        let isCurrent = i == count - 1
                        let fraction = CGFloat(point.totalMinutes) / maxH
                        let barH = max(size.height * fraction, 4)
                        let x = CGFloat(i) * (barW + gap)
                        let y = size.height - barH
                        let rect = CGRect(x: x, y: y, width: barW, height: barH)
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 4),
                            with: .color(color.opacity(isCurrent ? 1.0 : 0.22))
                        )
                    }
                }
                .frame(height: 90)

                // Duration label above current bar (computed from geometry)
                GeometryReader { geo in
                    let count = CGFloat(points.count)
                    let gap: CGFloat = points.count > 8 ? 5 : 7
                    let barW = (geo.size.width - gap * (count - 1)) / count
                    let maxH = CGFloat(maxMinutes)
                    let lastIdx = points.count - 1

                    if let last = points.last {
                        let fraction = CGFloat(last.totalMinutes) / maxH
                        let barH = max(geo.size.height * fraction, 4)
                        let x = CGFloat(lastIdx) * (barW + gap) + barW / 2
                        let y = geo.size.height - barH - 12

                        Text(minutesLabel(last.totalMinutes))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                            .position(x: x, y: max(y, 8))
                    }
                }
                .frame(height: 90)
                .allowsHitTesting(false)
            }

            // X-axis labels
            HStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                    let isCurrent = i == points.count - 1
                    Text(shortLabel(pt.label))
                        .font(.system(size: 11))
                        .foregroundStyle(isCurrent ? color : Color(hex: "A6A29C"))
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private func minutesLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h\(m)m"
    }

    private func shortLabel(_ label: String) -> String {
        let parts = label.split(separator: "-")
        // "2026-04" → "4月"
        if parts.count == 2, parts[0].count == 4, let month = Int(parts[1]) {
            return SharedL10n.tr("time.dashboard.month_short", month)
        }
        // "2026-06-17" → "6/17"
        if parts.count >= 3, let month = Int(parts[1]), let day = Int(String(parts[2]).prefix(2)) {
            return "\(month)/\(day)"
        }
        // Week "2026-06-15 ~ 2026-06-21" → take first date → "6/15"
        let spaceParts = label.split(separator: " ")
        if let first = spaceParts.first {
            let fp = first.split(separator: "-")
            if fp.count >= 3, let month = Int(fp[1]), let day = Int(String(fp[2]).prefix(2)) {
                return "\(month)/\(day)"
            }
        }
        return String(label.prefix(5))
    }
}

// MARK: - Flow Layout

struct DashboardFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Mobile Usage Section

private struct MobileUsageSectionView: View {
    let summary: MobileAppSummaryResponse
    let granularity: DashboardGranularity

    private var periodLabel: String {
        switch granularity {
        case .day: return SharedL10n.tr("time.dashboard.mobile.day")
        case .week: return SharedL10n.tr("time.dashboard.mobile.week")
        case .month: return SharedL10n.tr("time.dashboard.mobile.month")
        }
    }

    private var comparison: MobileAppComparison { summary.comparison }

    private var showBadge: Bool { abs(comparison.deltaDurationSeconds) > 0 }
    private var trendIsUp: Bool { comparison.durationTrend == "up" }
    private var badgeColor: Color { trendIsUp ? Color(hex: "C9485B") : Color(hex: "3FA78A") }

    private var maxSeconds: Int { summary.topApps.map(\.durationSeconds).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Total time row
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(periodLabel.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color(hex: "A6A29C"))
                    Text(summary.totalDurationLabel)
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(Color(hex: "C9485B"))
                        .kerning(-0.5)
                }
                Spacer()
                if showBadge {
                    Text(comparison.durationComparisonText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(badgeColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom, 14)

            // Divider before app list
            Rectangle()
                .fill(Color(hex: "E9E4DA"))
                .frame(height: 1)

            // Top 5 app rows
            let apps = summary.topApps
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                MobileAppRowView(app: app, maxSeconds: maxSeconds, isLast: index == apps.count - 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(0.05), radius: 24, x: 0, y: 8)
    }
}

private struct MobileAppRowView: View {
    let app: MobileTopApp
    let maxSeconds: Int
    let isLast: Bool

    private var fraction: CGFloat {
        guard maxSeconds > 0 else { return 0 }
        return CGFloat(app.durationSeconds) / CGFloat(maxSeconds)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text("\(app.rank)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color(hex: "A6A29C"))
                .frame(width: 14, alignment: .center)

            AppIconView(bundleId: app.bundleId, fallbackName: app.appName)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                Text(app.appName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1B1A"))
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hex: "F0ECE3"))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hex: "C9485B"))
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 5)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(app.durationLabel)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(hex: "1C1B1A"))
                Text(app.openCountLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "A6A29C"))
            }
            .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color(hex: "E9E4DA"))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - App Icon View

private struct AppIconView: View {
    let bundleId: String?
    let fallbackName: String
    @State private var iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: bundleId) {
            guard let bundleId, !bundleId.isEmpty else { return }
            await fetchIconURL(bundleId)
        }
    }

    private var fallbackView: some View {
        ZStack {
            Color(hex: "E9E4DA")
            Text(String(fallbackName.unicodeScalars.first.map(Character.init) ?? "?"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "6B6864"))
        }
    }

    private func fetchIconURL(_ bundleId: String) async {
        struct Lookup: Decodable {
            var results: [Entry]
            struct Entry: Decodable {
                var artworkUrl100: String?
                var artworkUrl512: String?
            }
        }
        for country in ["cn", "us"] {
            guard let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=\(country)&limit=1"),
                  let (data, _) = try? await URLSession.shared.data(from: lookupURL),
                  let lookup = try? JSONDecoder().decode(Lookup.self, from: data),
                  let entry = lookup.results.first,
                  let artStr = entry.artworkUrl100 ?? entry.artworkUrl512,
                  let url = URL(string: artStr) else { continue }
            iconURL = url
            return
        }
    }
}
