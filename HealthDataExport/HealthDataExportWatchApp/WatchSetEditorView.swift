import SwiftUI

/// "保存组" — log the real reps / weight (or duration) for a set, then save it as
/// completed. Also allows deleting the set.
struct WatchSetEditorView: View {
    let context: WatchWorkoutViewModel.SetContext
    let isSaving: Bool
    /// (weightKg?, reps?, durationSeconds?, distanceMeters?)
    let onSave: (Double?, Int?, Int?, Double?) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reps: Int
    @State private var weight: Double
    @State private var durationSeconds: Int
    @State private var distanceMeters: Double
    @State private var selectedField: EditorField?
    @State private var crownValue: Double = 0
    @State private var showDeleteConfirm = false
    @State private var showDistancePad = false
    @FocusState private var crownFocused: Bool

    private var isTimeBased: Bool { context.exercise.isTimeBased }
    private var isDistanceBased: Bool { ExerciseTrackingDisplay.isDistanceBased(context.exercise.trackingType) }
    private var showsWeight: Bool { context.exercise.trackingType == "weight_reps" }
    private enum EditorField {
        case durationMin
        case durationSec
        case reps
        case weight
        case distance
    }

    private var durationMinutes: Int { max(0, durationSeconds) / 60 }
    private var durationRemSeconds: Int { max(0, durationSeconds) % 60 }

    init(context: WatchWorkoutViewModel.SetContext, isSaving: Bool,
         onSave: @escaping (Double?, Int?, Int?, Double?) -> Void, onDelete: @escaping () -> Void) {
        self.context = context
        self.isSaving = isSaving
        self.onSave = onSave
        self.onDelete = onDelete
        let set = context.set
        _reps = State(initialValue: set.actualReps ?? set.plannedReps ?? 10)
        _weight = State(initialValue: set.actualWeightKg ?? set.plannedWeightKg ?? 0)
        _durationSeconds = State(initialValue: Self.initialDurationSeconds(from: set))
        _distanceMeters = State(initialValue: set.actualDistanceMeters ?? set.plannedDistanceMeters ?? 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if isTimeBased {
                        if isDistanceBased {
                            StepperRow(label: "距离", text: Self.distanceText(distanceMeters), isSelected: selectedField == .distance,
                                       onSelect: { select(.distance); showDistancePad = true },
                                       onMinus: { select(.distance); distanceMeters = max(0, distanceMeters - 10); crownValue = distanceMeters },
                                       onPlus: { select(.distance); distanceMeters += 10; crownValue = distanceMeters })
                            Text("点数字可直接输入")
                                .font(.system(size: 11))
                                .foregroundStyle(WK.muted)
                        }
                        timeStepperRow
                    } else {
                        StepperRow(label: "次数", text: "x\(reps)", isSelected: selectedField == .reps,
                                   onSelect: { select(.reps) },
                                   onMinus: { select(.reps); reps = max(0, reps - 1); crownValue = Double(reps) },
                                   onPlus: { select(.reps); reps += 1; crownValue = Double(reps) })
                        if showsWeight {
                            StepperRow(label: "重量", text: WK.weightText(weight), isSelected: selectedField == .weight,
                                       onSelect: { select(.weight) },
                                       onMinus: { select(.weight); weight = max(0, weight - 1); crownValue = weight },
                                       onPlus: { select(.weight); weight += 1; crownValue = weight })
                        }
                    }

                    Button(action: save) {
                        Group {
                            if isSaving { ProgressView().tint(.white) }
                            else { Text("保存").font(.system(size: 16, weight: .bold)) }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(WK.accent, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(HapticButtonStyle())
                    .disabled(isSaving)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .focusable(true)
                .focused($crownFocused)
                .digitalCrownRotation(
                    $crownValue,
                    from: crownRange.lowerBound,
                    through: crownRange.upperBound,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .onChange(of: crownValue) { _, newValue in
                    applyCrownValue(newValue)
                }
            }
            .background(WK.bg.ignoresSafeArea())
            .navigationTitle("保存组")
            .onAppear {
                if selectedField == nil {
                    select(isTimeBased ? .durationSec : .reps)
                }
                crownFocused = true
            }
            .sheet(isPresented: $showDistancePad) {
                WatchNumberPadView(title: "距离", unit: "m", initialValue: Int(distanceMeters.rounded())) { entered in
                    distanceMeters = Double(entered)
                    crownValue = distanceMeters
                }
            }
            .confirmationDialog("删除这一组?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    onDelete()
                }
                Button("取消", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash").foregroundStyle(WK.red)
                    }
                }
            }
        }
    }

    /// Minutes and seconds as two selectable boxes on one row ("MM : SS"). The
    /// +/- buttons and crown act on whichever box is selected. Minutes may exceed
    /// 60 (shown as e.g. "75:30") — the value is stored as total seconds.
    private var timeStepperRow: some View {
        HStack(spacing: 8) {
            circleButton("minus") { adjustTime(-1) }
            HStack(spacing: 6) {
                timeBox(String(format: "%02d", durationMinutes), selected: selectedField == .durationMin) { select(.durationMin) }
                Text(":")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                timeBox(String(format: "%02d", durationRemSeconds), selected: selectedField == .durationSec) { select(.durationSec) }
            }
            .frame(maxWidth: .infinity)
            circleButton("plus") { adjustTime(1) }
        }
    }

    private func timeBox(_ text: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(WK.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? WK.green : WK.line, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: onTap)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(WK.surface, in: Circle())
        }
        .buttonStyle(HapticButtonStyle())
    }

    /// Step the selected time box: minutes by ±1, seconds by ±5 (rolling into
    /// minutes). Defaults to the seconds box if a non-time field was selected.
    private func adjustTime(_ direction: Int) {
        if selectedField == .durationMin {
            durationSeconds = max(0, durationSeconds + direction * 60)
            crownValue = Double(durationMinutes)
        } else {
            selectedField = .durationSec
            durationSeconds = max(0, durationSeconds + direction * 5)
            crownValue = Double(durationRemSeconds)
        }
    }

    private func save() {
        if isTimeBased {
            onSave(nil, nil, durationSeconds, isDistanceBased ? distanceMeters : nil)
        } else if showsWeight {
            onSave(weight, reps, nil, nil)
        } else {
            onSave(nil, reps, nil, nil)
        }
    }

    private static func initialDurationSeconds(from set: FitnessSessionSet) -> Int {
        if let actual = set.actualDurationSeconds {
            return actual
        }
        if set.timerStatus == "running" {
            let live = set.timerStartedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
            return (set.timerAccumulatedSeconds ?? 0) + live
        }
        return set.plannedDurationSeconds ?? 60
    }

    private static func distanceText(_ meters: Double) -> String {
        "\(Int(meters.rounded()))m"
    }

    private var crownRange: ClosedRange<Double> {
        switch selectedField {
        case .durationMin:
            return 0...240
        case .durationSec:
            return 0...59
        case .reps:
            return 0...300
        case .weight:
            return 0...500
        case .distance:
            return 0...100_000
        case nil:
            return 0...100_000
        }
    }

    private func select(_ field: EditorField) {
        selectedField = field
        crownFocused = true
        switch field {
        case .durationMin:
            crownValue = Double(durationMinutes)
        case .durationSec:
            crownValue = Double(durationRemSeconds)
        case .reps:
            crownValue = Double(reps)
        case .weight:
            crownValue = weight
        case .distance:
            crownValue = distanceMeters
        }
    }

    private func applyCrownValue(_ value: Double) {
        switch selectedField {
        case .durationMin:
            durationSeconds = max(0, Int(value.rounded())) * 60 + durationRemSeconds
        case .durationSec:
            durationSeconds = durationMinutes * 60 + max(0, Int(value.rounded()))
        case .reps:
            reps = max(0, Int(value.rounded()))
        case .weight:
            weight = max(0, value.rounded())
        case .distance:
            distanceMeters = max(0, value.rounded())
        case nil:
            break
        }
    }
}

// MARK: - Number pad

/// A tap-to-type numeric keypad for entering a whole number directly — far
/// faster than the crown or +/- for large values like running distance.
private struct WatchNumberPadView: View {
    let title: String
    let unit: String
    let initialValue: Int
    let onDone: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entry: String

    init(title: String, unit: String, initialValue: Int, onDone: @escaping (Int) -> Void) {
        self.title = title
        self.unit = unit
        self.initialValue = initialValue
        self.onDone = onDone
        _entry = State(initialValue: initialValue > 0 ? String(initialValue) : "")
    }

    private var displayValue: String { entry.isEmpty ? "0" : entry }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(displayValue)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WK.muted)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 6)

            ForEach(0..<4) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3) { col in
                        keyView(for: row * 3 + col)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .background(WK.bg.ignoresSafeArea())
    }

    /// Grid layout: 1-9, then ⌫ / 0 / ✓.
    @ViewBuilder
    private func keyView(for index: Int) -> some View {
        switch index {
        case 0...8:
            digitKey("\(index + 1)")
        case 9:
            actionKey(symbol: "delete.left", tint: WK.red) {
                if !entry.isEmpty { entry.removeLast() }
            }
        case 10:
            digitKey("0")
        default:
            actionKey(symbol: "checkmark", tint: WK.green, filled: true) {
                onDone(Int(entry) ?? 0)
                dismiss()
            }
        }
    }

    private func digitKey(_ digit: String) -> some View {
        Button {
            // Cap length so the value stays sane and the label never overflows.
            if entry.count < 6 {
                entry = (entry == "0" ? "" : entry) + digit
            }
        } label: {
            Text(digit)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(WK.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(HapticButtonStyle())
    }

    private func actionKey(symbol: String, tint: Color, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(filled ? .white : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(filled ? tint : WK.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(HapticButtonStyle())
    }
}

private struct StepperRow: View {
    let label: String
    let text: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            circleButton("minus", action: onMinus)
            VStack(spacing: 0) {
                Text(text)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(WK.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? WK.green : WK.line, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: onSelect)
            circleButton("plus", action: onPlus)
        }
        .accessibilityLabel(label)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(WK.surface, in: Circle())
        }
        .buttonStyle(HapticButtonStyle())
    }
}

// MARK: - Rating

/// Personal effort rating (RPE 1–10) shown after the last set, then "提交" submits
/// and completes the session.
struct WatchRatingView: View {
    @Binding var rpe: Double
    let isSubmitting: Bool
    let onSubmit: () -> Void

    /// Crown drives the value directly; kept focused so rotation is captured as
    /// soon as the sheet appears.
    @FocusState private var crownFocused: Bool

    /// Per-level descriptors, matching the phone's rating sheet.
    private static let levels = [
        "极轻松", "很轻松", "轻松", "稍费力", "疲倦",
        "吃力", "很吃力", "非常吃力", "极度吃力", "精疲力竭",
    ]

    private let startDeg: Double = 135
    private let sweepDeg: Double = 270
    private let trackWidth: CGFloat = 12

    private var value: Int { min(10, max(1, Int(rpe.rounded()))) }
    private var label: String { Self.levels[value - 1] }
    private var color: Color {
        if value <= 3 { return Color(hex: "5E8FFF") }
        if value <= 6 { return Color(hex: "FF9F0A") }
        return Color(hex: "FF453A")
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - trackWidth / 2
            let activeSweep = (rpe - 1) / 9 * sweepDeg

            ZStack {
                arc(center: center, radius: radius, from: startDeg, sweep: sweepDeg)
                    .stroke(WK.line, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))

                if activeSweep > 0.5 {
                    arc(center: center, radius: radius, from: startDeg, sweep: activeSweep)
                        .stroke(
                            AngularGradient(
                                colors: [Color(hex: "8AABFF"), Color(hex: "A78BFF"), Color(hex: "FFCA6B"), Color(hex: "FF9F0A"), Color(hex: "FF453A")],
                                center: .center,
                                startAngle: .degrees(startDeg),
                                endAngle: .degrees(startDeg + sweepDeg)
                            ),
                            style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                        )
                }

                ForEach(1...10, id: \.self) { i in
                    Circle()
                        .fill(Double(i) <= rpe.rounded() ? Color.white.opacity(0.65) : Color.white.opacity(0.22))
                        .frame(width: 5, height: 5)
                        .position(point(center: center, radius: radius, for: Double(i)))
                }

                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(color, lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .position(point(center: center, radius: radius, for: rpe))

                Text("体能训练怎么样?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .position(x: center.x, y: center.y - radius * 0.42)

                Text(label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(width: radius * 1.3)
                    .position(x: center.x, y: center.y)

                Button(action: onSubmit) {
                    Group {
                        if isSubmitting { ProgressView().tint(.white) }
                        else { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(WK.accent, in: Circle())
                }
                .buttonStyle(HapticButtonStyle())
                .disabled(isSubmitting)
                .position(x: center.x, y: center.y + radius * 0.62)
            }
        }
        .background(WK.bg.ignoresSafeArea())
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            $rpe,
            from: 1,
            through: 10,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear { crownFocused = true }
    }

    private func arc(center: CGPoint, radius: CGFloat, from: Double, sweep: Double) -> Path {
        Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(from),
                        endAngle: .degrees(from + sweep),
                        clockwise: false)
        }
    }

    private func point(center: CGPoint, radius: CGFloat, for v: Double) -> CGPoint {
        let deg = startDeg + (v - 1) / 9 * sweepDeg
        let rad = deg * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(rad)),
                       y: center.y + radius * CGFloat(sin(rad)))
    }
}
