import SwiftUI

@MainActor
struct WatchTimeTrackerView: View {
    @StateObject private var store = ShortcutRecordStore()
    @State private var isListening = false
    @State private var heardText = ""
    @State private var isSendingStart = false
    @State private var isSendingStop = false
    @State private var statusMessage = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            WatchDesign.stage.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("FLOW")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(WatchDesign.brand)
                    .padding(.top, 14)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                dock
                    .padding(.bottom, 16)
            }
            .frame(width: 198, height: 242)
            .background(.black, in: RoundedRectangle(cornerRadius: 46, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        }
        .background(WatchDesign.stage)
        .onChange(of: isListening) { newValue in
            isInputFocused = newValue
        }
        .task {
            await refreshRunningSession()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session = store.activeSession {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(WatchDesign.green)
                            .frame(width: 7, height: 7)
                            .watchPulse()

                        Text("进行中")
                            .font(.system(size: 10, weight: .regular))
                            .tracking(2)
                            .foregroundStyle(WatchDesign.muted)
                    }

                    Text(session.task.name)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.76)

                    Text(timerText(from: session.startedAt, now: timeline.date))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(1)
                        .foregroundStyle(WatchDesign.accent)
                        .padding(.top, 2)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WatchDesign.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.top, 2)
                    }
                }
            }
        } else if isListening {
            VStack(spacing: 8) {
                Text("正在聆听")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(WatchDesign.accent)

                TextField("说出正在做的事", text: $heardText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        submitHeardText()
                    }
            }
        } else {
            Text("点麦克风\n说出正在做的事")
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(WatchDesign.muted)
                .multilineTextAlignment(.center)
        }
    }

    private var dock: some View {
        Group {
            if store.activeSession != nil {
                Button {
                    Task { await stopActiveSession() }
                } label: {
                    Image(systemName: isSendingStop ? "hourglass" : "square.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(WatchDesign.surface, in: Circle())
                        .overlay(Circle().stroke(WatchDesign.line, lineWidth: 1))
                }
                .buttonStyle(WatchPressButtonStyle())
                .disabled(isSendingStop)
            } else {
                Button {
                    toggleMic()
                } label: {
                    Image(systemName: isSendingStart ? "hourglass" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(isListening ? WatchDesign.green : WatchDesign.accent, in: Circle())
                        .shadow(color: (isListening ? WatchDesign.green : WatchDesign.accent).opacity(0.45), radius: 18, y: 6)
                        .watchMicLive(isActive: isListening)
                }
                .buttonStyle(WatchPressButtonStyle())
                .disabled(isSendingStart)
            }
        }
        .accessibilityLabel(store.activeSession == nil ? "开始语音记录" : "结束当前记录")
    }

    private func toggleMic() {
        if isListening {
            submitHeardText()
        } else {
            heardText = ""
            statusMessage = ""
            isListening = true
        }
    }

    private func submitHeardText() {
        let name = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isListening = false
            return
        }

        isListening = false
        heardText = ""
        let task = ShortcutTask(name: name, symbolName: "mic.fill", colorHex: WatchDesign.accentHex)
        Task { await startTask(task) }
    }

    private func startTask(_ task: ShortcutTask) async {
        let hadActiveSession = store.activeSession != nil
        isSendingStart = true
        statusMessage = ""

        if hadActiveSession {
            store.stop(note: "")
        }
        store.start(task)

        do {
            if hadActiveSession {
                try await ShortcutAPI.end(note: "")
            }
            try await ShortcutAPI.start(taskName: task.name)
        } catch {
            statusMessage = "同步失败"
        }

        isSendingStart = false
    }

    private func stopActiveSession() async {
        isSendingStop = true
        statusMessage = ""
        store.stop(note: "")

        do {
            try await ShortcutAPI.end(note: "")
        } catch {
            statusMessage = "结束同步失败"
        }

        isSendingStop = false
    }

    private func refreshRunningSession() async {
        do {
            let runningEntry = try await ShortcutAPI.running()
            store.syncRunningSession(runningEntry)
        } catch {
            statusMessage = "读取失败"
        }
    }

    private func timerText(from startDate: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startDate)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct WatchPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

private struct WatchPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: WatchDesign.green.opacity(isPulsing ? 0 : 0.5), radius: isPulsing ? 6 : 0)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

private struct WatchMicLiveModifier: ViewModifier {
    let isActive: Bool
    @State private var isRinging = false

    func body(content: Content) -> some View {
        content
            .overlay {
                Circle()
                    .stroke(WatchDesign.green.opacity(isActive && !isRinging ? 0.55 : 0), lineWidth: 2)
                    .scaleEffect(isRinging ? 1.38 : 1)
                    .opacity(isActive ? 1 : 0)
            }
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: isRinging)
            .onAppear {
                isRinging = true
            }
    }
}

private extension View {
    func watchPulse() -> some View {
        modifier(WatchPulseModifier())
    }

    func watchMicLive(isActive: Bool) -> some View {
        modifier(WatchMicLiveModifier(isActive: isActive))
    }
}

private enum WatchDesign {
    static let stage = Color(hex: "0B0B0C")
    static let surface = Color(hex: "1C1C1E")
    static let line = Color(hex: "2C2C2E")
    static let muted = Color(hex: "8A8F9C")
    static let brand = Color(hex: "5A5E68")
    static let accentHex = "FF7847"
    static let accent = Color(hex: accentHex)
    static let green = Color(hex: "22C55E")
}

private struct WatchTimeTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        WatchTimeTrackerView()
            .previewDisplayName("Apple Watch Time Tracker")
    }
}
