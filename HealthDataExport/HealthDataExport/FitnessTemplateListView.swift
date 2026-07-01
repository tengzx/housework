import SwiftUI
import Combine
import UIKit
import AudioToolbox


// MARK: - ViewModel

@MainActor
final class FitnessTemplateListViewModel: ObservableObject {
    @Published private(set) var templates: [FitnessTemplateSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await FitnessAPIClient.templates()
        } catch {
            errorMessage = "加载失败，请检查网络"
        }
    }

    func update(id: Int, name: String, trainingTheme: String?) async throws {
        try await FitnessAPIClient.updateTemplate(id: id, name: name, trainingTheme: trainingTheme, description: nil)
        await load()
    }

    func delete(id: Int) async {
        do {
            try await FitnessAPIClient.deleteTemplate(id: id)
            templates.removeAll { $0.id == id }
        } catch {
            errorMessage = "删除失败"
        }
    }
}

// MARK: - List View

struct FitnessTemplateListView: View {
    @StateObject private var vm = FitnessTemplateListViewModel()
    @State private var navigateToDetail: FitnessTemplateDetailPayload?
    @State private var navigateToEditor: FitnessTemplateEditorPayload?
    @State private var navigateToSession: FitnessWorkoutSessionPayload?
    @State private var showCreateSheet = false
    @State private var isCreating = false
    @State private var pendingCreation: (name: String, theme: String?)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "EFEFF2").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerView
                            .padding(.top, 6)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 18)

                        HStack(alignment: .center) {
                            Text("体能训练模板")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                        if vm.isLoading && vm.templates.isEmpty {
                            ProgressView().padding(40)
                        } else if vm.templates.isEmpty {
                            emptyState.padding(.top, 16)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(vm.templates) { tpl in
                                    TemplateGridCard(template: tpl)
                                        .onTapGesture {
                                            navigateToDetail = FitnessTemplateDetailPayload(
                                                id: tpl.id,
                                                name: tpl.name,
                                                exerciseCount: tpl.exerciseCount,
                                                setCount: tpl.setCount
                                            )
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if !vm.templates.isEmpty {
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 16)

                            Button { showCreateSheet = true } label: {
                                Text("编辑健身")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(hex: "1C1C1E"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color(hex: "C9C9CF"), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    )
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .refreshable { await vm.load() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $navigateToDetail) { payload in
                FitnessTemplateDetailView(payload: payload, onEdit: { editorPayload in
                    navigateToEditor = editorPayload
                }, onStart: { sessionPayload in
                    navigateToSession = sessionPayload
                })
            }
            .navigationDestination(item: $navigateToEditor) { payload in
                FitnessTemplateEditorView(
                    payload: payload,
                    onSaved: { await vm.load() },
                    onDeleted: {
                        await vm.load()
                        navigateToEditor = nil
                        navigateToDetail = nil
                    }
                )
            }
            .navigationDestination(item: $navigateToSession) { payload in
                FitnessActiveSessionView(payload: payload) { await vm.load() }
            }
        }
        // 新建 sheet
        .sheet(isPresented: $showCreateSheet, onDismiss: {
            if let creation = pendingCreation {
                pendingCreation = nil
                Task { @MainActor in
                    try? await createAndNavigate(name: creation.name, theme: creation.theme)
                }
            }
        }) {
            TemplateInfoSheet(
                title: "新建模板",
                confirmLabel: "创建",
                initialName: "",
                initialTheme: ""
            ) { name, theme in
                pendingCreation = (name: name, theme: theme)
            }
        }
        .alert("错误", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task { await vm.load() }
    }

    // MARK: Header

    private var headerView: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("健身")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text("过去 30 天")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "9A9AA0"))
            }
            HStack {
                Spacer()
                Button { showCreateSheet = true } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                        )
                }
                .disabled(isCreating)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(hex: "F6F6F8"))
            .frame(height: 200)
            .overlay(
                VStack(spacing: 12) {
                    Text("未添加任何模板")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Text("轻点"+"开始创建训练模板")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "7C7C82"))
                    Button { showCreateSheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                            Text("新建模板").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(Color(hex: "1C1C1E"), in: Capsule())
                    }
                }
            )
            .padding(.horizontal, 16)
    }

    // MARK: Helpers

    @MainActor private func createAndNavigate(name: String, theme: String?) async throws {
        isCreating = true
        defer { isCreating = false }
        let resp = try await FitnessAPIClient.createTemplate(name: name, description: nil, trainingTheme: theme?.isEmpty == true ? nil : theme)
        await vm.load()
        navigateToEditor = FitnessTemplateEditorPayload(id: resp.id, name: resp.name)
    }
}

// MARK: - Template Grid Card

private struct TemplateGridCard: View {
    let template: FitnessTemplateSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(template.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(template.exerciseCount) 种锻炼, \(template.setCount) 组")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "9A9AA0"))
                .padding(.top, 4)
                .lineLimit(1)

            Spacer(minLength: 14)

            HStack(alignment: .bottom, spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(volumeDigits, id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color(hex: "1C1C1E"))
                            .frame(minWidth: 21, minHeight: 30)
                            .padding(.horizontal, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(hex: "ECECEF"), lineWidth: 1)
                            )
                    }
                }
                Text("kg")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "9A9AA0"))
                    .padding(.bottom, 3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    private var volumeDigits: [(offset: Int, element: String)] {
        let str = template.estimatedVolumeKg > 0 ? String(Int(template.estimatedVolumeKg)) : "0"
        return Array(str.enumerated()).map { (offset: $0.offset, element: String($0.element)) }
    }
}
