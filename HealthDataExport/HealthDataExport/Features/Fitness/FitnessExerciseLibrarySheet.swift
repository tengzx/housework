import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class ExerciseLibraryViewModel: ObservableObject {
    @Published var allExercises: [FitnessExercise] = []
    @Published var searchText = ""
    @Published var selectedIds: Set<Int> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // Grouped by first character for default view
    var grouped: [(letter: String, items: [FitnessExercise])] {
        let list = filtered
        let dict = Dictionary(grouping: list) { ex -> String in
            let first = ex.name.prefix(1)
            return String(first).uppercased()
        }
        return dict.keys.sorted().map { k in (k, dict[k]!.sorted { $0.name < $1.name }) }
    }

    private var filtered: [FitnessExercise] {
        guard !searchText.isEmpty else { return allExercises }
        return allExercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var hasSelection: Bool { !selectedIds.isEmpty }
    var selectionCount: Int { selectedIds.count }

    func load() async {
        guard allExercises.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await FitnessAPIClient.exercises(pageSize: 200)
            allExercises = page.items.sorted { $0.name < $1.name }
        } catch {}
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await FitnessAPIClient.exercises(pageSize: 200)
            allExercises = page.items.sorted { $0.name < $1.name }
        } catch {}
    }

    func toggle(_ id: Int) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func confirmedExercises() -> [FitnessExercise] {
        allExercises.filter { selectedIds.contains($0.id) }
    }

    // MARK: CRUD

    func addExercise(_ exercise: FitnessExercise) {
        allExercises.append(exercise)
        allExercises.sort { $0.name < $1.name }
    }

    func updateExercise(_ exercise: FitnessExercise) {
        if let idx = allExercises.firstIndex(where: { $0.id == exercise.id }) {
            allExercises[idx] = exercise
        }
    }

    func deleteExercise(id: Int) async {
        do {
            try await FitnessAPIClient.deleteExercise(id: id)
            allExercises.removeAll { $0.id == id }
            selectedIds.remove(id)
        } catch {
            errorMessage = "删除失败，请检查网络"
        }
    }
}

// MARK: - Sheet form target

private enum LibraryFormTarget: Identifiable {
    case create
    case edit(FitnessExercise)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let e): return "edit-\(e.id)"
        }
    }
}

// MARK: - Sheet

struct FitnessExerciseLibrarySheet: View {
    let preselectedIds: Set<Int>
    let onConfirm: ([FitnessExercise]) -> Void

    @StateObject private var vm = ExerciseLibraryViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    @State private var formTarget: LibraryFormTarget?
    @State private var deleteTarget: FitnessExercise?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("取消") { Haptics.tap(); dismiss() }
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .font(.system(size: 17))
                Spacer()
                Text("库")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                Button {
                    Haptics.tap()
                    onConfirm(vm.confirmedExercises())
                    dismiss()
                } label: {
                    Text("添加\(vm.hasSelection ? "(\(vm.selectionCount))" : "")")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(vm.hasSelection ? Color(hex: "1C1C1E") : Color(hex: "BFBFC5"))
                }
                .disabled(!vm.hasSelection)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(hex: "9A9AA0"))
                    .font(.system(size: 16))
                TextField("搜索", text: $vm.searchText)
                    .focused($searchFocused)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                if !vm.searchText.isEmpty {
                    Button { Haptics.tap(); vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(hex: "9A9AA0"))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(hex: "E7E7EB"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Content
            if vm.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Custom exercise creation row
                        if vm.searchText.isEmpty {
                            Section {
                                CustomExerciseRow { formTarget = .create }
                                    .padding(.horizontal, 16)
                            } header: {
                                SectionLetterHeader(letter: "自定义")
                            }
                        }

                        // Grouped exercise list
                        ForEach(vm.grouped, id: \.letter) { group in
                            Section {
                                ForEach(group.items) { exercise in
                                    ExerciseLibraryRow(
                                        exercise: exercise,
                                        isSelected: vm.selectedIds.contains(exercise.id)
                                    ) {
                                        vm.toggle(exercise.id)
                                    }
                                    .padding(.horizontal, 16)
                                    .contextMenu(menuItems: {
                                        if !exercise.isSystem {
                                            Button {
                                                Haptics.tap()
                                                formTarget = .edit(exercise)
                                            } label: {
                                                Label("编辑", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                Haptics.tap()
                                                deleteTarget = exercise
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                    })

                                    if exercise.id != group.items.last?.id {
                                        Divider()
                                            .padding(.leading, 78)
                                    }
                                }
                            } header: {
                                SectionLetterHeader(letter: group.letter)
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .background(Color(hex: "F4F4F6").ignoresSafeArea())
        .task {
            vm.selectedIds = preselectedIds
            await vm.load()
        }
        // 新建 / 编辑动作（合并为单一 sheet，避免多 sheet modifier 导致闪退）
        .sheet(item: $formTarget) { target in
            switch target {
            case .create:
                FitnessExerciseFormSheet { exercise in
                    vm.addExercise(exercise)
                }
            case .edit(let exercise):
                FitnessExerciseFormSheet(existingExercise: exercise) { updated in
                    vm.updateExercise(updated)
                }
            }
        }
        // 删除确认
        .alert(
            "删除「\(deleteTarget?.name ?? "")」？",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
        ) {
            Button("取消", role: .cancel) { Haptics.tap(); deleteTarget = nil }
            Button("删除", role: .destructive) {
                Haptics.tap()
                guard let t = deleteTarget else { return }
                deleteTarget = nil
                Task { await vm.deleteExercise(id: t.id) }
            }
        } message: {
            Text("此操作不可撤销。")
        }
        .alert("错误", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好") { Haptics.tap(); vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}

// MARK: - Section header

private struct SectionLetterHeader: View {
    let letter: String
    var body: some View {
        Text(letter)
            .font(.system(size: 14))
            .foregroundStyle(Color(hex: "9A9AA0"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(hex: "F4F4F6"))
    }
}

// MARK: - Exercise row

private struct ExerciseLibraryRow: View {
    let exercise: FitnessExercise
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "F2F2F5"))
                .frame(width: 48, height: 48)
                .overlay(BarbellIcon())

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(exercise.category?.name ?? (exercise.isSystem ? "系统" : "自定义"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "9A9AA0"))
                    if !exercise.isSystem {
                        Text("·")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "BFBFC5"))
                        Text("自定义")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "6E5BF0"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(hex: "EEEBff"), in: Capsule())
                    }
                }
            }

            Spacer()

            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isSelected ? Color(hex: "1C1C1E") : Color.white)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(isSelected ? Color(hex: "1C1C1E") : Color(hex: "E4E4E9"), lineWidth: 1.5)
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "5B5B61"))
                    }
                }
            }
            .buttonStyle(HapticButtonStyle())
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { Haptics.tap(); onToggle() }
    }
}

// MARK: - Custom exercise row

private struct CustomExerciseRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "E7E7EB"))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(hex: "5B5B61"))
                    )
                Text("添加自定义动作")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "BFBFC5"))
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(HapticButtonStyle())

        Divider()
    }
}

// MARK: - Barbell icon

struct BarbellIcon: View {
    var color: Color = Color(hex: "C4451E")
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let barY = cy - 1
            let barH: CGFloat = 2
            ctx.fill(
                Path(roundedRect: CGRect(x: 6, y: barY, width: size.width - 12, height: barH), cornerRadius: 1),
                with: .color(Color(hex: "1C1C1E"))
            )
            for x in [CGFloat(3), size.width - 3 - 5] {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: cy - 5, width: 5, height: 10)),
                    with: .color(color)
                )
            }
        }
        .frame(width: 26, height: 26)
    }
}
