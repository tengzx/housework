import SwiftUI

/// A started session, used to drive navigation into the active workout screen.
struct WatchSessionRef: Hashable, Identifiable {
    let sessionId: Int
    let name: String
    var id: Int { sessionId }
}

/// Template detail: the exercises the template contains, plus the "开始训练"
/// button that creates a live session on the server and opens the active screen.
struct WatchTemplateDetailView: View {
    let templateId: Int
    let name: String

    @State private var detail: FitnessTemplateDetail?
    @State private var isLoading = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let detail {
                    Button {
                        Task { await start() }
                    } label: {
                        HStack {
                            if isStarting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "play.fill")
                                Text("开始训练").font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(WK.orange, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(HapticButtonStyle())
                    .disabled(isStarting || detail.exercises.isEmpty)

                    ForEach(detail.exercises) { exercise in
                        ExerciseSummaryRow(exercise: exercise)
                    }
                } else if isLoading {
                    ProgressView().padding(.top, 24)
                } else if let errorMessage {
                    VStack(spacing: 8) {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(WK.muted)
                        Button("重试") { Task { await load() } }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .background(WK.bg.ignoresSafeArea())
        .navigationTitle(name)
        .task { await load() }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await FitnessAPIClient.templateDetail(id: templateId)
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func start() async {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            let response = try await FitnessAPIClient.startSession(templateId: templateId, name: name)
            Haptics.notify(success: true)
            WatchActiveWorkoutStore.shared.startLocal(WatchSessionRef(sessionId: response.sessionId, name: name))
        } catch {
            Haptics.notify(success: false)
            errorMessage = "开始训练失败"
        }
    }
}

private struct ExerciseSummaryRow: View {
    let exercise: TemplateDetailExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("\(exercise.sets.count) 组")
                .font(.system(size: 11))
                .foregroundStyle(WK.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WK.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
