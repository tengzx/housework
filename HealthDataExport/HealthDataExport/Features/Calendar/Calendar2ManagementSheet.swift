import SwiftUI
import UIKit

enum ManagementTab: Equatable {
    case category, subcategory
}

struct Calendar2ManagementSheet: View {
    let initialTab: ManagementTab
    let store: TimeCalendarStore
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: ManagementTab
    @State private var cats: [EditableCat]
    @State private var subs: [EditableSub]
    @State private var expandedId: String?
    @State private var selectedSubCatId: String?
    @State private var nextId = 1000
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var originalCats: [EditableCat]
    @State private var originalSubs: [EditableSub]

    private let paletteHex = [
        "C7948B", "EF5B4E", "F2864A",
        "F1C13D", "45C24A", "7BA62D",
        "34A6F1", "6B78F0", "8A56C8",
        "7C8893", "B9B9BF"
    ]

    init(initialTab: ManagementTab, store: TimeCalendarStore, onDone: @escaping () -> Void) {
        self.initialTab = initialTab
        self.store = store
        self.onDone = onDone
        _tab = State(initialValue: initialTab)
        let editableCats = store.categories.map { EditableCat(from: $0) }
        _originalCats = State(initialValue: editableCats)
        _cats = State(initialValue: editableCats)
        let allSubs = store.categories.flatMap { cat in
            cat.types.map { EditableSub(id: $0.id, name: $0.label, catId: cat.id, tracksFocus: $0.tracksFocus) }
        }
        _originalSubs = State(initialValue: allSubs)
        _subs = State(initialValue: allSubs)
        _selectedSubCatId = State(initialValue: editableCats.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: "DADADE"))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HStack {
                Text(tab == .category ? "管理分类" : "管理小类")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "23232A"))
                Spacer()
                if isSaving {
                    ProgressView()
                        .padding(.trailing, 4)
                }
                Button("完成") {
                    Haptics.tap()
                    Task { await saveAll() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSaving ? Color(hex: "B5B5BC") : Calendar2Style.accent)
                .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            HStack(spacing: 4) {
                tabSegment("分类", value: .category)
                tabSegment("小类", value: .subcategory)
            }
            .padding(4)
            .background(Color(hex: "F0F0F3"), in: RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                if tab == .category {
                    categoryList
                } else {
                    subcategoryList
                }
            }
        }
        .background(Calendar2Style.sheet)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .alert("保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { Haptics.tap(); errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Tab Segment

    private func tabSegment(_ title: String, value: ManagementTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                tab = value
                if value == .subcategory && selectedSubCatId == nil {
                    selectedSubCatId = cats.first?.id
                }
                expandedId = nil
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tab == value ? Color(hex: "23232A") : Color(hex: "8A8A92"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    tab == value ? Color.white : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .shadow(color: tab == value ? .black.opacity(0.12) : .clear, radius: 3, x: 0, y: 1)
        }
        .buttonStyle(HapticButtonStyle())
    }

    // MARK: - Category List

    private var categoryList: some View {
        VStack(spacing: 0) {
            ForEach($cats) { $cat in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                expandedId = expandedId == cat.id ? nil : cat.id
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(cat.color)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(HapticButtonStyle())

                        TextField("分类名称", text: $cat.name)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "23232A"))

                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                expandedId = expandedId == cat.id ? nil : cat.id
                            }
                        } label: {
                            Text("改色")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color(hex: "9A9AA2"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(HapticButtonStyle())

                        let catId = cat.id
                        Button {
                            withAnimation {
                                cats.removeAll { $0.id == catId }
                                subs.removeAll { $0.catId == catId }
                                if expandedId == catId { expandedId = nil }
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "C6C6CC"))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(HapticButtonStyle())
                    }
                    .padding(.vertical, 14)

                    if expandedId == cat.id {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(paletteHex.indices, id: \.self) { i in
                                    let hex = paletteHex[i]
                                    Button {
                                        cat.hexColor = hex
                                        expandedId = nil
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 28, height: 28)
                                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                                    }
                                    .buttonStyle(HapticButtonStyle())
                                }
                            }
                            .padding(.leading, 42)
                            .padding(.trailing, 20)
                        }
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 20)
                Divider().padding(.leading, 20)
            }

            Button {
                let id = "new_cat_\(nextId)"
                let colorIdx = nextId % paletteHex.count
                nextId += 1
                withAnimation {
                    cats.append(EditableCat(id: id, name: "", hexColor: paletteHex[colorIdx]))
                    expandedId = id
                }
            } label: {
                addRowLabel("＋ 新建分类")
            }
            .buttonStyle(HapticButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Subcategory List

    private var subcategoryList: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cats) { cat in
                        let isOn = selectedSubCatId == cat.id
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedSubCatId = cat.id
                                expandedId = nil
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(cat.color).frame(width: 8, height: 8)
                                Text(cat.name.isEmpty ? "（无名称）" : cat.name)
                                    .font(.system(size: 14, weight: isOn ? .semibold : .medium))
                                    .foregroundStyle(isOn ? Color(hex: "2A2A30") : Color(hex: "4A4A52"))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                isOn ? cat.color.opacity(0.13) : Color(hex: "F5F5F7"),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isOn ? cat.color.opacity(0.55) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(Calendar2PressStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            Divider()

            let filteredSubs = subs.indices.filter { subs[$0].catId == selectedSubCatId }
            let selCat = cats.first(where: { $0.id == selectedSubCatId })
            let selColor = selCat?.color ?? Color(hex: "B9B9BF")

            if filteredSubs.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无小类")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "B5B5BC"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredSubs, id: \.self) { idx in
                        subRow(idx: idx, tint: selColor)
                        Divider().padding(.leading, 20)
                    }
                }
            }

            let addCatName = selCat?.name.isEmpty == false ? selCat!.name : "未分类"
            Button {
                let id = "new_sub_\(nextId)"
                nextId += 1
                withAnimation {
                    subs.append(EditableSub(id: id, name: "", catId: selectedSubCatId ?? cats.first?.id ?? "", tracksFocus: false))
                    expandedId = id
                }
            } label: {
                addRowLabel("＋ 新建「\(addCatName)」的小类")
            }
            .buttonStyle(HapticButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .disabled(selectedSubCatId == nil)
        }
    }

    private func subRow(idx: Int, tint: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                    .padding(.leading, 10)

                TextField("小类名称", text: $subs[idx].name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "23232A"))

                Button {
                    subs[idx].tracksFocus.toggle()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "scope")
                            .font(.system(size: 12, weight: .medium))
                        Text("专注")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(subs[idx].tracksFocus ? Calendar2Style.accent : Color(hex: "C6C6CC"))
                    .frame(width: 34, height: 30)
                }
                .buttonStyle(HapticButtonStyle())

                let subId = subs[idx].id
                Button {
                    withAnimation {
                        subs.removeAll { $0.id == subId }
                        if expandedId == subId { expandedId = nil }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "C6C6CC"))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(HapticButtonStyle())
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    private func addRowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Calendar2Style.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Calendar2Style.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        Calendar2Style.accent.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
    }

    // MARK: - Save

    @MainActor
    private func saveAll() async {
        isSaving = true
        defer { isSaving = false }

        let origCatIds = Set(originalCats.map(\.id))
        let origSubIds = Set(originalSubs.map(\.id))
        let currentCatIds = Set(cats.map(\.id))
        let currentSubIds = Set(subs.map(\.id))

        let deletedCatIds = origCatIds.subtracting(currentCatIds)
        let deletedSubIds = origSubIds.subtracting(currentSubIds)
        let newCats = cats.filter { !origCatIds.contains($0.id) && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let newSubs = subs.filter { !origSubIds.contains($0.id) && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let modifiedCats = cats.filter { cat in
            guard origCatIds.contains(cat.id),
                  let orig = originalCats.first(where: { $0.id == cat.id }) else { return false }
            return orig.name != cat.name || orig.hexColor != cat.hexColor
        }
        let modifiedSubs = subs.filter { sub in
            guard origSubIds.contains(sub.id),
                  let orig = originalSubs.first(where: { $0.id == sub.id }) else { return false }
            return orig.name != sub.name || orig.tracksFocus != sub.tracksFocus
        }

        do {
            // 1. Delete removed types first (API requires no types before deleting a category)
            for id in deletedSubIds {
                try await store.deleteType(id: id)
            }

            // 2. Delete removed categories
            for id in deletedCatIds {
                try await store.deleteCategory(id: id)
            }

            // 3. Create new categories; map temp IDs → server IDs for type creation
            var idMap: [String: String] = [:]
            for cat in newCats {
                let created = try await store.createCategory(name: cat.name, hexColor: "#\(cat.hexColor)")
                idMap[cat.id] = created.id
            }

            // 4. Update modified categories
            for cat in modifiedCats {
                try await store.updateCategory(id: cat.id, name: cat.name, hexColor: "#\(cat.hexColor)")
            }

            // 5. Create new types (resolve temp category IDs)
            for sub in newSubs {
                let realCatId = idMap[sub.catId] ?? sub.catId
                try await store.createType(categoryId: realCatId, name: sub.name, tracksFocus: sub.tracksFocus)
            }

            // 6. Update modified types
            for sub in modifiedSubs {
                try await store.updateType(id: sub.id, name: sub.name, tracksFocus: sub.tracksFocus)
            }

            // 7. Reload to ensure consistent state
            try await store.reloadCategories()

            // Refresh local state from server data (keep sheet open)
            let freshCats = store.categories.map { EditableCat(from: $0) }
            let freshSubs = store.categories.flatMap { cat in
                cat.types.map { EditableSub(id: $0.id, name: $0.label, catId: cat.id, tracksFocus: $0.tracksFocus) }
            }
            cats = freshCats
            subs = freshSubs
            originalCats = freshCats
            originalSubs = freshSubs

            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Local model types

private struct EditableCat: Identifiable {
    var id: String
    var name: String
    var hexColor: String  // without #

    var color: Color { Color(hex: hexColor) }

    init(id: String, name: String, hexColor: String) {
        self.id = id
        self.name = name
        self.hexColor = hexColor
    }

    init(from category: Calendar2Category) {
        id = category.id
        name = category.label
        let uiColor = UIColor(category.color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        hexColor = String(format: "%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded()))
    }
}

private struct EditableSub: Identifiable {
    var id: String
    var name: String
    var catId: String
    var tracksFocus: Bool
}
