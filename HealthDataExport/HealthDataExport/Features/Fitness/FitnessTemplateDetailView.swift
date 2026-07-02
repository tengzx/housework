import SwiftUI
import Combine

// MARK: - Template Detail View

struct FitnessTemplateDetailPayload: Hashable, Identifiable {
    let id: Int
    let name: String
    let exerciseCount: Int
    let setCount: Int
}

@MainActor
final class FitnessTemplateDetailViewModel: ObservableObject {
    let payload: FitnessTemplateDetailPayload
    @Published private(set) var detail: FitnessTemplateDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isStarting = false
    @Published var errorMessage: String?
    @Published var startMessage: String?

    init(payload: FitnessTemplateDetailPayload) {
        self.payload = payload
    }

    var title: String { detail?.name ?? payload.name }

    var exerciseCount: Int { detail?.exercises.count ?? payload.exerciseCount }

    var setCount: Int {
        detail?.exercises.reduce(0) { $0 + $1.sets.count } ?? payload.setCount
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await FitnessAPIClient.templateDetail(id: payload.id)
        } catch {
            errorMessage = "加载失败，请检查网络"
        }
    }

    func startWorkout() async -> FitnessWorkoutSessionPayload? {
        guard !isStarting else { return nil }
        isStarting = true
        startMessage = nil
        defer { isStarting = false }
        do {
            let response = try await FitnessAPIClient.startSession(templateId: payload.id, name: title)
            return FitnessWorkoutSessionPayload(sessionId: response.sessionId, name: title)
        } catch {
            startMessage = "开始训练失败，请检查网络"
            return nil
        }
    }
}

struct FitnessTemplateDetailView: View {
    let payload: FitnessTemplateDetailPayload
    let onEdit: (FitnessTemplateEditorPayload) -> Void
    let onStart: (FitnessWorkoutSessionPayload) -> Void

    @StateObject private var vm: FitnessTemplateDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        payload: FitnessTemplateDetailPayload,
        onEdit: @escaping (FitnessTemplateEditorPayload) -> Void,
        onStart: @escaping (FitnessWorkoutSessionPayload) -> Void
    ) {
        self.payload = payload
        self.onEdit = onEdit
        self.onStart = onStart
        _vm = StateObject(wrappedValue: FitnessTemplateDetailViewModel(payload: payload))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.title)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .padding(.horizontal, 20)
                            .padding(.top, 26)

                        Text("\(vm.exerciseCount) 种锻炼, \(vm.setCount) 组")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "8E8E93"))
                            .padding(.horizontal, 20)
                            .padding(.top, 6)

                        if vm.isLoading && vm.detail == nil {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        } else if let detail = vm.detail {
                            VStack(spacing: 12) {
                                ForEach(detail.exercises) { exercise in
                                    TemplateDetailExerciseRow(exercise: exercise)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                        } else if let errorMessage = vm.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "F05B5B"))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 48)
                        }

                        devicePickerRow
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                    .padding(.bottom, 150)
                }
            }

            bottomActions
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await vm.load()
        }
        .alert("提示", isPresented: Binding(
            get: { vm.startMessage != nil },
            set: { if !$0 { vm.startMessage = nil } }
        )) {
            Button("好") { Haptics.tap(); vm.startMessage = nil }
        } message: {
            Text(vm.startMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button { Haptics.tap(); dismiss() } label: {
                Circle()
                    .fill(Color(hex: "F1F1F4"))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var devicePickerRow: some View {
        HStack {
            Text("设备")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "9A9AA0"))
            Spacer()
            HStack(spacing: 8) {
                Text("仅 iPhone")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "5A5078").opacity(0.07), radius: 20, y: 6)
        .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                onEdit(FitnessTemplateEditorPayload(id: payload.id, name: vm.title))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                    Text("编辑")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(Color(hex: "1C1C1E"))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color(hex: "F1F1F4"), in: Capsule())
            }

            Button {
                Haptics.tap()
                Task {
                    if let sessionPayload = await vm.startWorkout() {
                        onStart(sessionPayload)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if vm.isStarting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text("开始")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color(hex: "1C1C1E"), in: Capsule())
            }
            .disabled(vm.setCount == 0 || vm.isStarting)
            .opacity(vm.setCount == 0 ? 0.45 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .padding(.top, 24)
        .background(
            LinearGradient(
                colors: [.white, .white.opacity(0.96), .white.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()
        )
    }
}

private struct TemplateDetailExerciseRow: View {
    let exercise: TemplateDetailExercise

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "F6F6F8"))
                .frame(width: 58, height: 58)
                .overlay(BarbellIcon())

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                Text("\(exercise.categoryName ?? "——") · \(exercise.sets.count) 组")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "EEEEF1"), lineWidth: 1)
        )
    }
}
