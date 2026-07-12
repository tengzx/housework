import SwiftUI
import Combine
import UIKit
import AudioToolbox


// MARK: - Workout Rating Sheet

private struct RPELevel {
    let label: String
    let description: String
}

private let rpeLevels: [RPELevel] = [
    RPELevel(label: L10n.tr("fitness.rating.level.1.label"), description: L10n.tr("fitness.rating.level.1.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.2.label"), description: L10n.tr("fitness.rating.level.2.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.3.label"), description: L10n.tr("fitness.rating.level.3.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.4.label"), description: L10n.tr("fitness.rating.level.4.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.5.label"), description: L10n.tr("fitness.rating.level.5.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.6.label"), description: L10n.tr("fitness.rating.level.6.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.7.label"), description: L10n.tr("fitness.rating.level.7.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.8.label"), description: L10n.tr("fitness.rating.level.8.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.9.label"), description: L10n.tr("fitness.rating.level.9.description")),
    RPELevel(label: L10n.tr("fitness.rating.level.10.label"), description: L10n.tr("fitness.rating.level.10.description")),
]

struct WorkoutRatingSheet: View {
    @Binding var rpe: Double
    /// Whether this session came from a template (only then can we offer to
    /// update it). When false the "保存并更新模版" button is hidden.
    var canUpdateTemplate: Bool = false
    let onSave: () -> Void
    var onSaveAndUpdateTemplate: () -> Void = {}

    private var level: RPELevel { rpeLevels[max(0, min(9, Int(rpe.rounded()) - 1)) ] }

    private var labelColor: Color {
        if rpe <= 3 { return Color(hex: "5E8FFF") }
        if rpe <= 6 { return Color(hex: "FF9F0A") }
        return Color(hex: "FF453A")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(L10n.tr("fitness.rating.title"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .padding(.bottom, 36)

            ArcRPESlider(value: $rpe)
                .frame(width: 340, height: 320)

            VStack(spacing: 6) {
                Text(level.label)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(labelColor)
                Text(level.description)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onSave) {
                    Text(L10n.tr("fitness.rating.save_workout"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: "1C1C1E"), in: Capsule())
                }
                .buttonStyle(HapticButtonStyle())

                if canUpdateTemplate {
                    Button(action: onSaveAndUpdateTemplate) {
                        Text(L10n.tr("fitness.rating.save_and_update_template"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                                    .overlay(Capsule().stroke(Color(hex: "D8D8DE"), lineWidth: 1.5))
                            )
                    }
                    .buttonStyle(HapticButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(hex: "F2F2F7").ignoresSafeArea())
    }
}

struct ArcRPESlider: View {
    @Binding var value: Double

    private let startDeg: Double = 135
    private let sweepDeg: Double = 270
    private let trackWidth: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
            let radius = min(size.width, size.height) / 2 - trackWidth - 8

            ZStack {
                // Background track
                arcPath(center: center, radius: radius, from: startDeg, sweep: sweepDeg)
                    .stroke(Color(hex: "E5E5EA"), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))

                // Active gradient track
                let activeSweep = (value - 1) / 9 * sweepDeg
                if activeSweep > 0 {
                    arcPath(center: center, radius: radius, from: startDeg, sweep: max(activeSweep, 2))
                        .stroke(
                            AngularGradient(
                                colors: [Color(hex: "8AABFF"), Color(hex: "A78BFF"), Color(hex: "FFCA6B"), Color(hex: "FF9F0A")],
                                center: .center,
                                startAngle: .degrees(startDeg),
                                endAngle: .degrees(startDeg + sweepDeg)
                            ),
                            style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                        )
                }

                // Tick dots
                ForEach(1...10, id: \.self) { i in
                    let pos = pointOnArc(center: center, radius: radius, for: Double(i))
                    Circle()
                        .fill(Double(i) <= value.rounded() ? Color.white.opacity(0.65) : Color(hex: "C7C7CC"))
                        .frame(width: 6, height: 6)
                        .position(pos)
                }

                // Handle
                let hp = pointOnArc(center: center, radius: radius, for: value)
                let handleColor = self.handleColor
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(handleColor, lineWidth: 3.5))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .position(hp)

                // Center value
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 76, weight: .heavy, design: .rounded))
                    .foregroundStyle(handleColor)
                    .position(x: center.x, y: center.y - 8)

                // "1" and "10" labels
                let p1 = pointOnArc(center: center, radius: radius + trackWidth + 10, for: 1)
                let p10 = pointOnArc(center: center, radius: radius + trackWidth + 10, for: 10)
                Text("1")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .position(x: p1.x - 4, y: p1.y + 4)
                Text("10")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .position(x: p10.x + 4, y: p10.y + 4)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + 10)
                        updateValue(from: drag.location, center: center)
                    }
            )
        }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, from: Double, sweep: Double) -> Path {
        Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(from),
                        endAngle: .degrees(from + sweep),
                        clockwise: false)
        }
    }

    private func pointOnArc(center: CGPoint, radius: CGFloat, for v: Double) -> CGPoint {
        let deg = startDeg + (v - 1) / 9 * sweepDeg
        let rad = deg * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(rad)), y: center.y + radius * CGFloat(sin(rad)))
    }

    private func updateValue(from point: CGPoint, center: CGPoint) {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        // Map angle into arc range [startDeg, startDeg+sweepDeg]
        var normalized = angle - startDeg
        if normalized < 0 { normalized += 360 }
        // Treat angles just past the end (in the gap) as clamped
        let fraction = max(0, min(1, normalized / sweepDeg))
        // Snap to integer values
        let raw = fraction * 9 + 1
        value = (raw).rounded().clamped(to: 1...10)
    }

    private var handleColor: Color {
        if value <= 3 { return Color(hex: "8AABFF") }
        if value <= 6 { return Color(hex: "FF9F0A") }
        return Color(hex: "FF453A")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
