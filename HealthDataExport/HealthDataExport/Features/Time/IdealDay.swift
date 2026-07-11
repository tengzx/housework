import SwiftUI
import UserNotifications
import Combine

enum IdealDayKind: String, CaseIterable, Codable, Identifiable {
    case proactive = "PROACTIVE"
    case obligation = "OBLIGATION"
    case recovery = "RECOVERY"
    case distraction = "DISTRACTION"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .proactive: "主动投入"
        case .obligation: "必要事务"
        case .recovery: "恢复充电"
        case .distraction: "分心消耗"
        }
    }
    var subtitle: String {
        switch self {
        case .proactive: "工作、学习、成长、深度陪伴等"
        case .obligation: "家务、接送、做饭、杂事等"
        case .recovery: "睡眠、休息、运动、放松等"
        case .distraction: "刷手机、短视频、无意义娱乐等"
        }
    }
    var symbol: String {
        switch self {
        case .proactive: "scope"
        case .obligation: "lock.fill"
        case .recovery: "leaf.fill"
        case .distraction: "iphone"
        }
    }
    var color: Color {
        switch self {
        case .proactive: Color(hex: "596AF0")
        case .obligation: Color(hex: "FFB51B")
        case .recovery: Color(hex: "58C99A")
        case .distraction: Color(hex: "FF6245")
        }
    }
}

struct IdealDayAllocation: Codable, Identifiable, Equatable {
    var kind: IdealDayKind
    var targetMinutes: Int
    var id: IdealDayKind { kind }
}

struct IdealDayProfile: Codable, Equatable {
    var allocations: [IdealDayAllocation]
    var checkTimes: [String]
    var remindersEnabled: Bool

    static let defaultProfile = IdealDayProfile(
        allocations: [
            .init(kind: .proactive, targetMinutes: 360),
            .init(kind: .obligation, targetMinutes: 360),
            .init(kind: .recovery, targetMinutes: 600),
            .init(kind: .distraction, targetMinutes: 120)
        ],
        checkTimes: ["12:00", "18:00"],
        remindersEnabled: true
    )

    func minutes(for kind: IdealDayKind) -> Int {
        allocations.first(where: { $0.kind == kind })?.targetMinutes ?? 0
    }
    var allocatedMinutes: Int { allocations.reduce(0) { $0 + $1.targetMinutes } }
}

private struct IdealDayEnvelope: Codable { let profile: IdealDayProfile }
private struct IdealDayComparison: Decodable {
    struct Deviation: Decodable { let kind: IdealDayKind; let targetMinutes: Int; let actualMinutes: Int; let status: String }
    let deviations: [Deviation]
}

enum IdealDayAPI {
    static func profile() async throws -> IdealDayProfile {
        let response = try await HTTPClient.shared.decode(
            IdealDayEnvelope.self,
            url: TimeCalendarAPI.baseURL.appendingPathComponent("ideal-day"),
            method: .get
        )
        return response.profile
    }

    static func save(_ profile: IdealDayProfile) async throws -> IdealDayProfile {
        let response = try await HTTPClient.shared.decode(
            IdealDayEnvelope.self,
            url: TimeCalendarAPI.baseURL.appendingPathComponent("ideal-day"),
            method: .put,
            body: profile
        )
        return response.profile
    }

    fileprivate static func comparison() async throws -> [IdealDayComparison.Deviation] {
        var components = URLComponents(url: TimeCalendarAPI.baseURL.appendingPathComponent("ideal-day/comparison"), resolvingAgainstBaseURL: false)!
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        components.queryItems = [
            .init(name: "date", value: formatter.string(from: .now)),
            .init(name: "timeZone", value: TimeZone.current.identifier)
        ]
        return try await HTTPClient.shared.decode(IdealDayComparison.self, url: components.url!, method: .get).deviations
    }
}

@MainActor
final class IdealDayStore: ObservableObject {
    static let shared = IdealDayStore()
    @Published var profile: IdealDayProfile
    @Published var statusMessage = ""
    @Published var isSaving = false

    private let cacheKey = "ideal-day.profile.v1"
    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(IdealDayProfile.self, from: data) {
            profile = cached
        } else {
            profile = .defaultProfile
        }
    }

    func load() async {
        do {
            profile = try await IdealDayAPI.profile()
            cache()
        } catch {
            // Offline-first: the editor remains useful before the backend is upgraded.
            statusMessage = "当前使用本机保存的理想配置"
        }
        await notifyIfExceeded()
    }

    private func notifyIfExceeded() async {
        guard profile.remindersEnabled,
              let exceeded = try? await IdealDayAPI.comparison().filter({ $0.status == "EXCEEDED" }),
              !exceeded.isEmpty else { return }
        await IdealDayReminderScheduler.presentExceeded(exceeded)
    }

    func save(_ value: IdealDayProfile) async -> Bool {
        profile = value
        cache()
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await IdealDayAPI.save(value)
            cache()
            await IdealDayReminderScheduler.reschedule(profile: profile)
            statusMessage = "已保存"
            return true
        } catch {
            await IdealDayReminderScheduler.reschedule(profile: profile)
            statusMessage = "已保存在本机，连接 Life OS 后会再次同步"
            return false
        }
    }

    private func cache() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

enum IdealDayReminderScheduler {
    private static let prefix = "ideal-day.check."

    static func reschedule(profile: IdealDayProfile) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard profile.remindersEnabled else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        for time in profile.checkTimes {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "理想一天 · 阶段检查"
            content.body = "看看今天四类时间是否有不足，及时调整接下来的安排。"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: parts[0], minute: parts[1]),
                repeats: true
            )
            try? await center.add(.init(identifier: prefix + time, content: content, trigger: trigger))
        }
    }

    fileprivate static func presentExceeded(_ values: [IdealDayComparison.Deviation]) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "理想一天 · 已超出目标"
        content.body = values.map { "\($0.kind.title) 已用 \($0.actualMinutes / 60)h\($0.actualMinutes % 60)m，目标 \($0.targetMinutes / 60)h\($0.targetMinutes % 60)m" }.joined(separator: "；")
        content.sound = .default
        center.removeDeliveredNotifications(withIdentifiers: ["ideal-day.exceeded"])
        try? await center.add(.init(identifier: "ideal-day.exceeded", content: content, trigger: nil))
    }
}

struct IdealDayView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: IdealDayStore
    @State private var draft: IdealDayProfile

    init(store: IdealDayStore) {
        self.store = store
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    allocationRing.frame(width: 230, height: 230).padding(.top, 10)
                    allocationCard
                    flexibleCard
                    reminderCard
                    Text("💡 理想一天是你的方向盘。系统会把实际记录与其对比，超出目标及时提醒，并在中午 12 点、晚上 6 点检查不足。")
                        .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(6)
                        .padding(.horizontal, 18)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(Color(hex: "F7F8FC").ignoresSafeArea())
            .navigationTitle("理想一天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.isSaving ? "保存中…" : "保存") {
                        Task { _ = await store.save(draft); dismiss() }
                    }.disabled(store.isSaving || draft.allocatedMinutes > 1440)
                }
            }
        }
    }

    private var allocationRing: some View {
        ZStack {
            ForEach(Array(IdealDayKind.allCases.enumerated()), id: \.element) { index, kind in
                let start = Double(draft.allocations.prefix(index).reduce(0) { $0 + $1.targetMinutes }) / 1440
                let end = start + Double(draft.minutes(for: kind)) / 1440
                Circle().trim(from: start + 0.006, to: max(start + 0.006, end - 0.006))
                    .stroke(kind.color, style: StrokeStyle(lineWidth: 28, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 3) {
                Text("24h").font(.system(size: 42, weight: .bold, design: .rounded))
                Text("时间分配").foregroundStyle(.secondary)
            }
        }
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("时间配比").font(.headline); Spacer(); Text("拖动可调整时长").font(.caption).foregroundStyle(.secondary) }
            ForEach(IdealDayKind.allCases) { kind in
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbol).foregroundStyle(kind.color).frame(width: 38, height: 38).background(kind.color.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).font(.system(size: 16, weight: .semibold))
                            Text(kind.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(hoursText(draft.minutes(for: kind))).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    }
                    Slider(value: binding(for: kind), in: 0...1440, step: 30).tint(kind.color)
                }
            }
        }
        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var flexibleCard: some View {
        HStack {
            Image(systemName: "hourglass").foregroundStyle(Color(hex: "6674E8"))
            VStack(alignment: .leading) { Text("弹性时间").font(.headline); Text("未规划的时间，可自由分配").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text(hoursText(max(0, 1440 - draft.allocatedMinutes))).foregroundStyle(Color(hex: "6674E8")).font(.title3).monospacedDigit()
        }.padding(18).background(Color(hex: "EEF1FF"), in: RoundedRectangle(cornerRadius: 20))
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("偏差提醒", isOn: $draft.remindersEnabled).font(.headline)
            Text("超过目标时提醒；目标不足会在 12:00 和 18:00 定期排查。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func binding(for kind: IdealDayKind) -> Binding<Double> {
        Binding {
            Double(draft.minutes(for: kind))
        } set: { value in
            guard let index = draft.allocations.firstIndex(where: { $0.kind == kind }) else { return }
            draft.allocations[index].targetMinutes = Int(value)
        }
    }

    private func hoursText(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)h" : String(format: "%.1fh", Double(minutes) / 60)
    }
}
