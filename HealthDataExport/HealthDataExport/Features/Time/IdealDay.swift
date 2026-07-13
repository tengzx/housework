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
        case .proactive: SharedL10n.tr("time.dashboard.load_kind.proactive")
        case .obligation: SharedL10n.tr("time.dashboard.load_kind.obligation")
        case .recovery: SharedL10n.tr("time.dashboard.load_kind.recovery")
        case .distraction: SharedL10n.tr("time.dashboard.load_kind.distraction")
        }
    }
    var subtitle: String {
        switch self {
        case .proactive: SharedL10n.tr("ideal_day.kind.proactive.subtitle")
        case .obligation: SharedL10n.tr("ideal_day.kind.obligation.subtitle")
        case .recovery: SharedL10n.tr("ideal_day.kind.recovery.subtitle")
        case .distraction: SharedL10n.tr("ideal_day.kind.distraction.subtitle")
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
        // Keep the same semantic palette as the Analysis dashboard.
        case .proactive: Color(hex: "E8743B")
        case .obligation: Color(hex: "6B7A99")
        case .recovery: Color(hex: "3FA78A")
        case .distraction: Color(hex: "C9485B")
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
            .init(kind: .obligation, targetMinutes: 240),
            .init(kind: .recovery, targetMinutes: 540),
            .init(kind: .distraction, targetMinutes: 60)
        ],
        checkTimes: ["12:00", "18:00"],
        remindersEnabled: true
    )

    func minutes(for kind: IdealDayKind) -> Int {
        allocations.first(where: { $0.kind == kind })?.targetMinutes ?? 0
    }
    var allocatedMinutes: Int { allocations.reduce(0) { $0 + $1.targetMinutes } }
    var flexibleMinutes: Int { max(0, 1440 - allocatedMinutes) }

    mutating func normalize() {
        var remaining = 1440
        allocations = IdealDayKind.allCases.map { kind in
            let value = min(max(0, minutes(for: kind)), remaining)
            remaining -= value
            return IdealDayAllocation(kind: kind, targetMinutes: value)
        }
    }
}

private struct IdealDayEnvelope: Codable { let profile: IdealDayProfile }
struct IdealDayComparison: Decodable {
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
    @Published private(set) var todayActualMinutes: [IdealDayKind: Int] = [:]

    private let cacheKey = "ideal-day.profile.v1"
    private let exceededSignatureKey = "ideal-day.last-exceeded-signature.v1"
    private let forcedReminderPrefix = "ideal-day.forced-reminder."
    private let forcedReminderCooldown: TimeInterval = 30 * 60
    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(IdealDayProfile.self, from: data) {
            profile = cached
        } else {
            profile = .defaultProfile
        }
        profile.normalize()
    }

    func load() async {
        do {
            profile = try await IdealDayAPI.profile()
            profile.normalize()
            cache()
        } catch {
            // Offline-first: the editor remains useful before the backend is upgraded.
            statusMessage = SharedL10n.tr("ideal_day.status.local_profile")
        }
        await loadTodayComparison()
    }

    func loadTodayComparison(forceReminder: Bool = false) async {
        guard let deviations = try? await IdealDayAPI.comparison() else { return }
        todayActualMinutes = Dictionary(uniqueKeysWithValues: deviations.map { ($0.kind, $0.actualMinutes) })
        guard profile.remindersEnabled else { return }
        let exceeded = deviations.filter { $0.status == "EXCEEDED" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let signature = dayFormatter.string(from: .now) + ":" + exceeded.map(\.kind.rawValue).sorted().joined(separator: ",")
        let defaults = UserDefaults.standard
        let previousSignature = defaults.string(forKey: exceededSignatureKey)
        if forceReminder {
            let now = Date().timeIntervalSince1970
            let eligible = exceeded.filter { deviation in
                let last = defaults.double(forKey: forcedReminderPrefix + deviation.kind.rawValue)
                return last == 0 || now - last >= forcedReminderCooldown
            }
            guard !eligible.isEmpty else { return }
            for deviation in eligible {
                defaults.set(now, forKey: forcedReminderPrefix + deviation.kind.rawValue)
            }
            defaults.set(signature, forKey: exceededSignatureKey)
            await IdealDayReminderScheduler.presentExceeded(eligible)
        } else if !exceeded.isEmpty, signature != previousSignature {
            let now = Date().timeIntervalSince1970
            defaults.set(signature, forKey: exceededSignatureKey)
            for deviation in exceeded {
                defaults.set(now, forKey: forcedReminderPrefix + deviation.kind.rawValue)
            }
            await IdealDayReminderScheduler.presentExceeded(exceeded)
        }
    }

    func save(_ value: IdealDayProfile) async -> Bool {
        var normalized = value
        normalized.normalize()
        profile = normalized
        cache()
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await IdealDayAPI.save(normalized)
            profile.normalize()
            cache()
            await IdealDayReminderScheduler.reschedule(profile: profile)
            await loadTodayComparison()
            statusMessage = SharedL10n.tr("ideal_day.status.saved")
            return true
        } catch {
            await IdealDayReminderScheduler.reschedule(profile: profile)
            statusMessage = SharedL10n.tr("ideal_day.status.saved_local_pending_sync")
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
            content.title = SharedL10n.tr("ideal_day.notification.check_title")
            content.body = SharedL10n.tr("ideal_day.notification.check_body")
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
        content.title = SharedL10n.tr("ideal_day.notification.exceeded_title")
        content.body = values.map {
            SharedL10n.tr(
                "ideal_day.notification.exceeded_item",
                $0.kind.title,
                hoursAndMinutesText($0.actualMinutes),
                hoursAndMinutesText($0.targetMinutes)
            )
        }.joined(separator: SharedL10n.tr("ideal_day.notification.separator"))
        content.sound = .default
        center.removeDeliveredNotifications(withIdentifiers: ["ideal-day.exceeded"])
        try? await center.add(.init(identifier: "ideal-day.exceeded", content: content, trigger: nil))
    }

    private static func hoursAndMinutesText(_ minutes: Int) -> String {
        SharedL10n.tr("ideal_day.format.hours_minutes", minutes / 60, minutes % 60)
    }
}

struct IdealDayView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: IdealDayStore
    @State private var draft: IdealDayProfile
    @State private var editingKind: IdealDayKind?
    @State private var allocationError = ""
    @State private var showAllocationError = false

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
                    Text(SharedL10n.tr("ideal_day.hint"))
                        .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(6)
                        .padding(.horizontal, 18)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .refreshable { await store.loadTodayComparison() }
            .background(Calendar2Style.bg.ignoresSafeArea())
            .navigationTitle(SharedL10n.tr("ideal_day.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(SharedL10n.tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.isSaving ? SharedL10n.tr("common.loading") : SharedL10n.tr("common.save")) {
                        Task { _ = await store.save(draft); dismiss() }
                    }.disabled(store.isSaving || draft.allocatedMinutes > 1440)
                }
            }
            .sheet(item: $editingKind) { kind in
                ManualTimeEntrySheet(
                    kind: kind,
                    initialMinutes: draft.minutes(for: kind),
                    maximumMinutes: draft.minutes(for: kind) + draft.flexibleMinutes
                ) { requestedMinutes in
                    applyManualEntry(requestedMinutes, for: kind)
                }
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
            }
            .alert(SharedL10n.tr("ideal_day.alert.allocation_failed_title"), isPresented: $showAllocationError) {
                Button(SharedL10n.tr("ideal_day.alert.acknowledged"), role: .cancel) {}
            } message: {
                Text(allocationError)
            }
            .task {
                // Always prefer the authenticated user's Life OS record. When
                // none exists, the backend and local model share the same
                // sensible starter allocation.
                await store.load()
                draft = store.profile
            }
        }
        .tint(Color(hex: "0A84FF"))
    }

    private var allocationRing: some View {
        ZStack {
            Circle()
                .stroke(flexibleColor.opacity(0.22), lineWidth: 28)
            ForEach(ringSegments) { segment in
                Circle().trim(from: segment.start + ringGap, to: max(segment.start + ringGap, segment.end - ringGap))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 28, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 3) {
                Text("24h").font(.system(size: 42, weight: .bold, design: .rounded))
                Text(SharedL10n.tr("ideal_day.allocation")).foregroundStyle(.secondary)
            }
        }
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(SharedL10n.tr("ideal_day.allocation_ratio")).font(.headline)
                Spacer()
                Text(SharedL10n.tr("ideal_day.drag_hint")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(IdealDayKind.allCases) { kind in
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbol).foregroundStyle(kind.color).frame(width: 38, height: 38).background(kind.color.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).font(.system(size: 16, weight: .semibold))
                            Text(kind.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Button {
                                editingKind = kind
                            } label: {
                                HStack(spacing: 4) {
                                    Text(hoursText(draft.minutes(for: kind)))
                                    Image(systemName: "pencil").font(.caption2)
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(kind.color)
                            }
                            .buttonStyle(.plain)
                            Text(SharedL10n.tr("ideal_day.actual_value", hoursAndMinutesText(store.todayActualMinutes[kind] ?? 0)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    PlanActualSlider(
                        plannedMinutes: binding(for: kind),
                        actualMinutes: store.todayActualMinutes[kind] ?? 0,
                        color: kind.color
                    )
                    HStack(spacing: 14) {
                        Label(SharedL10n.tr("ideal_day.plan_value", hoursText(draft.minutes(for: kind))), systemImage: "circle.fill")
                            .foregroundStyle(kind.color.opacity(0.48))
                        Label(SharedL10n.tr("ideal_day.actual_value", hoursAndMinutesText(store.todayActualMinutes[kind] ?? 0)), systemImage: "circle.bottomhalf.filled")
                            .foregroundStyle(kind.color)
                        Spacer()
                        Text("24h").foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
            }
        }
        .padding(18).background(Calendar2Style.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var flexibleCard: some View {
        HStack {
            Image(systemName: "hourglass").foregroundStyle(flexibleColor)
            VStack(alignment: .leading) {
                Text(SharedL10n.tr("ideal_day.flexible_time")).font(.headline)
                Text(SharedL10n.tr("ideal_day.flexible_time_subtitle")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(hoursText(draft.flexibleMinutes)).foregroundStyle(flexibleColor).font(.title3).monospacedDigit()
        }.padding(18).background(flexibleColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(SharedL10n.tr("ideal_day.reminder_toggle"), isOn: $draft.remindersEnabled).font(.headline)
            Text(SharedL10n.tr("ideal_day.reminder_description"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Calendar2Style.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func binding(for kind: IdealDayKind) -> Binding<Double> {
        Binding {
            Double(draft.minutes(for: kind))
        } set: { value in
            guard let index = draft.allocations.firstIndex(where: { $0.kind == kind }) else { return }
            let otherMinutes = draft.allocatedMinutes - draft.allocations[index].targetMinutes
            // The selected category may only consume the day's remaining budget.
            // This invariant keeps total allocated + flexible time exactly 24 h.
            draft.allocations[index].targetMinutes = min(Int(value), 1440 - otherMinutes)
        }
    }

    private var flexibleColor: Color { Color(hex: "C8CFDD") }
    private var ringGap: Double { 0.003 }

    private struct RingSegment: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    private var ringSegments: [RingSegment] {
        var cursor = 0.0
        var result = IdealDayKind.allCases.compactMap { kind -> RingSegment? in
            let share = Double(draft.minutes(for: kind)) / 1440
            defer { cursor += share }
            guard share > 0 else { return nil }
            return RingSegment(id: kind.rawValue, start: cursor, end: cursor + share, color: kind.color)
        }
        let flexibleShare = Double(draft.flexibleMinutes) / 1440
        if flexibleShare > 0 {
            result.append(RingSegment(id: "FLEXIBLE", start: cursor, end: 1, color: flexibleColor))
        }
        return result
    }

    private func hoursText(_ minutes: Int) -> String {
        minutes % 60 == 0
            ? SharedL10n.tr("ideal_day.format.hours_only", minutes / 60)
            : SharedL10n.tr("ideal_day.format.hours_decimal", Double(minutes) / 60)
    }

    private func hoursAndMinutesText(_ minutes: Int) -> String {
        SharedL10n.tr("ideal_day.format.hours_minutes", minutes / 60, minutes % 60)
    }


    private func applyManualEntry(_ requestedMinutes: Int, for kind: IdealDayKind) {
        guard requestedMinutes <= 1440 else {
            presentAllocationError(SharedL10n.tr("ideal_day.error.single_category_over_24h"))
            return
        }
        let currentMinutes = draft.minutes(for: kind)
        let availableMinutes = currentMinutes + draft.flexibleMinutes
        guard requestedMinutes <= availableMinutes else {
            presentAllocationError(SharedL10n.tr("ideal_day.error.flexible_time_insufficient"))
            return
        }
        guard let index = draft.allocations.firstIndex(where: { $0.kind == kind }) else { return }
        draft.allocations[index].targetMinutes = requestedMinutes
    }

    private func presentAllocationError(_ message: String) {
        allocationError = message
        // Present after the input alert has finished dismissing.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            showAllocationError = true
        }
    }
}

/// One shared 24-hour rail: the upper half is the editable plan and the lower
/// half is today's read-only actual value. Only the plan owns a draggable thumb.
private struct PlanActualSlider: View {
    @Binding var plannedMinutes: Double
    let actualMinutes: Int
    let color: Color
    @State private var dragAxis: Axis?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let planWidth = width * min(1, max(0, plannedMinutes / 1440))
            let actualWidth = width * min(1, max(0, Double(actualMinutes) / 1440))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(color.opacity(0.45)).frame(width: planWidth, height: 7)
                    Rectangle().fill(color).frame(width: actualWidth, height: 7)
                }
                .clipShape(Capsule())
                // Keep the two endpoints on separate vertical lanes. The whole
                // rail remains draggable, so the visible plan handle can stay
                // compact without reducing its touch target.
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(color.opacity(0.55), lineWidth: 2))
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .offset(
                        x: min(max(0, planWidth - 5), max(0, width - 10)),
                        y: -6
                    )
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { gesture in
                        if dragAxis == nil {
                            dragAxis = abs(gesture.translation.width) > abs(gesture.translation.height) * 1.2
                                ? .horizontal : .vertical
                        }
                        guard dragAxis == .horizontal else { return }
                        let raw = min(max(0, gesture.location.x / max(width, 1)), 1) * 1440
                        plannedMinutes = (raw / 30).rounded() * 30
                    }
                    .onEnded { _ in dragAxis = nil }
            )
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SharedL10n.tr("ideal_day.accessibility.plan_actual_label"))
        .accessibilityValue(SharedL10n.tr("ideal_day.accessibility.plan_actual_value", Int(plannedMinutes), actualMinutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: plannedMinutes = min(1440, plannedMinutes + 30)
            case .decrement: plannedMinutes = max(0, plannedMinutes - 30)
            @unknown default: break
            }
        }
    }
}

private struct ManualTimeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: IdealDayKind
    let maximumMinutes: Int
    let onConfirm: (Int) -> Void
    @State private var hours: String
    @State private var minutes: String
    @FocusState private var focusedField: Field?

    private enum Field { case hours, minutes }

    init(kind: IdealDayKind, initialMinutes: Int, maximumMinutes: Int, onConfirm: @escaping (Int) -> Void) {
        self.kind = kind
        self.maximumMinutes = maximumMinutes
        self.onConfirm = onConfirm
        _hours = State(initialValue: String(initialMinutes / 60))
        _minutes = State(initialValue: String(initialMinutes % 60))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    timeField(title: SharedL10n.tr("ideal_day.time_field.hours"), text: $hours, field: .hours)
                    Text(":").font(.title.bold()).foregroundStyle(.secondary)
                    timeField(title: SharedL10n.tr("ideal_day.time_field.minutes"), text: $minutes, field: .minutes)
                }
                Text(SharedL10n.tr("ideal_day.maximum_allocatable", maximumMinutes / 60, maximumMinutes % 60))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding(20)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(SharedL10n.tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(SharedL10n.tr("common.ok")) {
                        let total = min(Int(hours) ?? 0, 24) * 60 + min(Int(minutes) ?? 0, 59)
                        dismiss()
                        onConfirm(total)
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(SharedL10n.tr("common.done")) { focusedField = nil }
                }
            }
            .onAppear { focusedField = .hours }
        }
    }

    private func timeField(title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: text.wrappedValue) { _, newValue in
                    text.wrappedValue = String(newValue.filter(\.isNumber).prefix(2))
                }
        }
        .frame(maxWidth: .infinity)
    }
}
