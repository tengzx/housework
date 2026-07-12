import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class ExerciseLibraryViewModel: ObservableObject {
    /// Exercises loaded from the server for the current query, accumulated across pages.
    @Published private(set) var loaded: [FitnessExercise] = []
    @Published var searchText = ""
    @Published var selectedIds: Set<Int> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    // Filters
    @Published private(set) var categories: [ExerciseCategory] = []
    @Published private(set) var muscleGroups: [MuscleGroup] = []   // top-level body parts only
    @Published private(set) var selectedCategoryId: Int?
    @Published private(set) var selectedMuscleGroupId: Int?

    var hasActiveFilter: Bool { selectedCategoryId != nil || selectedMuscleGroupId != nil }

    private let pageSize = 25
    private var currentPage = 0
    private var total = 0
    private var canLoadMore = true
    private var searchTask: Task<Void, Never>?

    /// Already-selected exercises passed in by the caller. Kept as full objects
    /// (reconstructed if needed) so they remain visible and are never dropped on
    /// confirm even when they fall outside the currently loaded page(s).
    private var preselected: [FitnessExercise] = []
    /// Every exercise we've ever resolved, keyed by id — the source of truth for
    /// building the confirmed selection.
    private var knownById: [Int: FitnessExercise] = [:]

    // The list actually shown. In browse mode (empty search) we surface any
    // preselected exercises that the server pages haven't returned yet, so the
    // user can see what's already added. In search mode we show server matches only.
    private var visibleExercises: [FitnessExercise] {
        // Only surface preselected-but-not-loaded exercises in plain browse mode
        // (no search text, no active filter) — otherwise honor the query as-is.
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty && !hasActiveFilter {
            let loadedIds = Set(loaded.map { $0.id })
            let missing = preselected.filter { !loadedIds.contains($0.id) }
            return (missing + loaded).sorted { $0.name < $1.name }
        }
        return loaded
    }

    /// Ids of the last few visible rows — used to prefetch the next page before
    /// the user reaches the very bottom.
    private var prefetchTriggerIds: Set<Int> {
        Set(visibleExercises.suffix(prefetchDistance).map { $0.id })
    }
    private let prefetchDistance = 5

    // Grouped by first character for default view
    var grouped: [(letter: String, items: [FitnessExercise])] {
        let dict = Dictionary(grouping: visibleExercises) { ex -> String in
            String(ex.name.prefix(1)).uppercased()
        }
        return dict.keys.sorted().map { k in (k, dict[k]!.sorted { $0.name < $1.name }) }
    }

    var hasSelection: Bool { !selectedIds.isEmpty }
    var selectionCount: Int { selectedIds.count }

    func setPreselected(_ exercises: [FitnessExercise]) {
        preselected = exercises
        selectedIds = Set(exercises.map { $0.id })
        for ex in exercises { knownById[ex.id] = ex }
    }

    func loadInitial() async {
        guard loaded.isEmpty else { return }
        // Load filter options in the background so the exercise list can render
        // immediately instead of waiting on the category/muscle endpoints.
        Task { await loadFilters() }
        await fetch(reset: true)
    }

    private func loadFilters() async {
        guard categories.isEmpty && muscleGroups.isEmpty else { return }
        async let cats = try? FitnessAPIClient.exerciseCategories()
        async let muscles = try? FitnessAPIClient.muscleGroups()
        categories = await cats ?? []
        // Top-level body parts only (no parent).
        muscleGroups = (await muscles ?? []).filter { $0.parentId == nil }
    }

    func setCategory(_ id: Int?) {
        guard selectedCategoryId != id else { return }
        selectedCategoryId = id
        Task { await fetch(reset: true) }
    }

    func setMuscleGroup(_ id: Int?) {
        guard selectedMuscleGroupId != id else { return }
        selectedMuscleGroupId = id
        Task { await fetch(reset: true) }
    }

    var selectedCategoryName: String {
        categories.first { $0.id == selectedCategoryId }?.name ?? L10n.tr("fitness.library.all_equipment")
    }

    var selectedMuscleGroupName: String {
        muscleGroups.first { $0.id == selectedMuscleGroupId }?.name ?? L10n.tr("fitness.library.all_muscle_groups")
    }

    func onSearchChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await self?.fetch(reset: true)
        }
    }

    func loadMoreIfNeeded(currentItem: FitnessExercise) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard prefetchTriggerIds.contains(currentItem.id) else { return }
        Task { await fetch(reset: false) }
    }

    private func fetch(reset: Bool) async {
        if reset {
            currentPage = 0
            canLoadMore = true
            isLoading = true
        } else {
            guard canLoadMore else { return }
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        let nextPage = currentPage + 1
        let kw = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let page = try await FitnessAPIClient.exercises(
                keyword: kw.isEmpty ? nil : kw,
                categoryId: selectedCategoryId,
                muscleGroupId: selectedMuscleGroupId,
                page: nextPage,
                pageSize: pageSize
            )
            if reset { loaded = [] }
            // Backend returns exercises already sorted by name, so we just
            // append in order (dedup guards against overlap between pages).
            var seen = Set(loaded.map { $0.id })
            for ex in page.items where seen.insert(ex.id).inserted {
                loaded.append(ex)
                knownById[ex.id] = ex
            }
            currentPage = nextPage
            total = page.total
            canLoadMore = loaded.count < total && !page.items.isEmpty
        } catch {
            canLoadMore = false
        }
    }

    func toggle(_ id: Int) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func confirmedExercises() -> [FitnessExercise] {
        selectedIds.compactMap { knownById[$0] }
    }

    // MARK: CRUD

    func addExercise(_ exercise: FitnessExercise) {
        knownById[exercise.id] = exercise
        if !loaded.contains(where: { $0.id == exercise.id }) {
            loaded.append(exercise)
            loaded.sort { $0.name < $1.name }
        }
    }

    func updateExercise(_ exercise: FitnessExercise) {
        knownById[exercise.id] = exercise
        if let idx = loaded.firstIndex(where: { $0.id == exercise.id }) {
            loaded[idx] = exercise
        }
    }

    func deleteExercise(id: Int) async {
        do {
            try await FitnessAPIClient.deleteExercise(id: id)
            loaded.removeAll { $0.id == id }
            knownById[id] = nil
            preselected.removeAll { $0.id == id }
            selectedIds.remove(id)
        } catch {
            errorMessage = L10n.tr("fitness.library.delete_failed")
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
    let preselected: [FitnessExercise]
    let onConfirm: ([FitnessExercise]) -> Void

    @StateObject private var vm = ExerciseLibraryViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    @State private var formTarget: LibraryFormTarget?
    @State private var deleteTarget: FitnessExercise?
    @State private var detailTarget: FitnessExercise?
    @State private var showMuscleFilter = false
    @State private var showCategoryFilter = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(L10n.tr("common.cancel")) { Haptics.tap(); dismiss() }
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .font(.system(size: 17))
                Spacer()
                Text(L10n.tr("fitness.library.title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                Button {
                    Haptics.tap()
                    onConfirm(vm.confirmedExercises())
                    dismiss()
                } label: {
                    Text(vm.hasSelection ? L10n.tr("fitness.library.confirm_add_count", vm.selectionCount) : L10n.tr("fitness.library.confirm_add"))
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
                TextField(L10n.tr("fitness.library.search_placeholder"), text: $vm.searchText)
                    .focused($searchFocused)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .autocorrectionDisabled()
                    .onChange(of: vm.searchText) { _ in vm.onSearchChanged() }
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

            // Filters
            filterBar

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
                                SectionLetterHeader(letter: L10n.tr("fitness.library.custom_section"))
                            }
                        }

                        // Grouped exercise list
                        ForEach(vm.grouped, id: \.letter) { group in
                            Section {
                                ForEach(group.items) { exercise in
                                    ExerciseLibraryRow(
                                        exercise: exercise,
                                        isSelected: vm.selectedIds.contains(exercise.id),
                                        onToggle: { vm.toggle(exercise.id) },
                                        onOpenDetail: { detailTarget = exercise }
                                    )
                                    .padding(.horizontal, 16)
                                    .onAppear { vm.loadMoreIfNeeded(currentItem: exercise) }
                                    .contextMenu(menuItems: {
                                        if !exercise.isSystem {
                                            Button {
                                                Haptics.tap()
                                                formTarget = .edit(exercise)
                                            } label: {
                                                Label(L10n.tr("common.edit"), systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                Haptics.tap()
                                                deleteTarget = exercise
                                            } label: {
                                                Label(L10n.tr("common.delete"), systemImage: "trash")
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

                        if vm.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .background(Color(hex: "F4F4F6").ignoresSafeArea())
        .task {
            vm.setPreselected(preselected)
            await vm.loadInitial()
        }
        // 动作详情 + 动作指导（点击行弹出；加号才添加到模版）
        .sheet(item: $detailTarget) { exercise in
            FitnessExerciseDetailSheet(exercise: exercise)
        }
        // 肌群筛选
        .sheet(isPresented: $showMuscleFilter) {
            FilterPickerSheet(
                title: L10n.tr("fitness.library.muscle_group"),
                allLabel: L10n.tr("fitness.library.all_muscle_groups"),
                options: vm.muscleGroups.map { ($0.id, $0.name) },
                selectedId: vm.selectedMuscleGroupId,
                onApply: { vm.setMuscleGroup($0) }
            )
        }
        // 分类筛选
        .sheet(isPresented: $showCategoryFilter) {
            FilterPickerSheet(
                title: L10n.tr("fitness.library.equipment"),
                allLabel: L10n.tr("fitness.library.all_equipment"),
                options: vm.categories.map { ($0.id, $0.name) },
                selectedId: vm.selectedCategoryId,
                onApply: { vm.setCategory($0) }
            )
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
            L10n.tr("fitness.library.delete_exercise_title", deleteTarget?.name ?? ""),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
        ) {
            Button(L10n.tr("common.cancel"), role: .cancel) { Haptics.tap(); deleteTarget = nil }
            Button(L10n.tr("common.delete"), role: .destructive) {
                Haptics.tap()
                guard let t = deleteTarget else { return }
                deleteTarget = nil
                Task { await vm.deleteExercise(id: t.id) }
            }
        } message: {
            Text(L10n.tr("fitness.library.delete_exercise_message"))
        }
        .alert(L10n.tr("common.error"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(L10n.tr("common.ok")) { Haptics.tap(); vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Filter bar

    @ViewBuilder
    private var filterBar: some View {
        if !vm.categories.isEmpty || !vm.muscleGroups.isEmpty {
            HStack(spacing: 10) {
                if !vm.muscleGroups.isEmpty {
                    FilterButton(
                        title: vm.selectedMuscleGroupName,
                        isActive: vm.selectedMuscleGroupId != nil
                    ) { Haptics.tap(); showMuscleFilter = true }
                }
                if !vm.categories.isEmpty {
                    FilterButton(
                        title: vm.selectedCategoryName,
                        isActive: vm.selectedCategoryId != nil
                    ) { Haptics.tap(); showCategoryFilter = true }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Filter summary button

private struct FilterButton: View {
    let title: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(isActive ? .white : Color(hex: "1C1C1E"))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isActive ? Color(hex: "1C1C1E") : Color(hex: "E7E7EB"),
                in: Capsule()
            )
        }
        .buttonStyle(HapticButtonStyle())
    }
}

// MARK: - Filter picker sheet (single-select)

struct FilterPickerSheet: View {
    let title: String
    let allLabel: String
    let options: [(id: Int, name: String)]
    let selectedId: Int?
    let onApply: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: Int?

    init(title: String, allLabel: String, options: [(id: Int, name: String)], selectedId: Int?, onApply: @escaping (Int?) -> Void) {
        self.title = title
        self.allLabel = allLabel
        self.options = options
        self.selectedId = selectedId
        self.onApply = onApply
        _choice = State(initialValue: selectedId)
    }

    private var chosenName: String {
        options.first { $0.id == choice }?.name ?? allLabel
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.tr("fitness.library.filter_title", title))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "1C1C1E"))
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    row(id: nil, name: allLabel)
                    ForEach(options, id: \.id) { opt in
                        row(id: opt.id, name: opt.name)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            Button {
                Haptics.tap()
                onApply(choice)
                dismiss()
            } label: {
                Text(L10n.tr("fitness.library.apply_filter", chosenName))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "1C1C1E"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(HapticButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .background(Color(hex: "F4F4F6").ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func row(id: Int?, name: String) -> some View {
        let isSelected = choice == id
        return Button {
            Haptics.tap()
            choice = id
        } label: {
            HStack {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color(hex: "1C1C1E") : Color(hex: "C4C4C9"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color(hex: "1C1C1E") : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(HapticButtonStyle())
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
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ExerciseThumbnail(urlString: exercise.imageUrl, size: 48, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(exercise.category?.name ?? (exercise.isSystem ? L10n.tr("fitness.library.system_badge") : L10n.tr("fitness.library.custom_badge")))
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "9A9AA0"))
                    if !exercise.isSystem {
                        Text("·")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "BFBFC5"))
                        Text(L10n.tr("fitness.library.custom_badge"))
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
        .onTapGesture { Haptics.tap(); onOpenDetail() }
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
                Text(L10n.tr("fitness.library.add_custom_exercise"))
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
