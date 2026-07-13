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
            cat.types.map { EditableSub(id: $0.id, name: $0.label, catId: cat.id, tracksFocus: $0.tracksFocus, loadKindOverride: $0.loadKindOverride) }
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
                Text(tab == .category ? L10n.tr("calendar.management.title.category") : L10n.tr("calendar.management.title.subcategory"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Calendar2Style.text)
                Spacer()
                if isSaving {
                    ProgressView()
                        .padding(.trailing, 4)
                }
                Button(L10n.tr("common.done")) {
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
                tabSegment(L10n.tr("calendar.management.tab.category"), value: .category)
                tabSegment(L10n.tr("calendar.management.tab.subcategory"), value: .subcategory)
            }
            .padding(4)
            .background(Calendar2Style.surface2, in: RoundedRectangle(cornerRadius: 11))
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
        .alert(L10n.tr("calendar.management.save_failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.tr("common.ok")) { Haptics.tap(); errorMessage = nil }
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
                .foregroundStyle(tab == value ? Calendar2Style.text : Calendar2Style.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    tab == value ? Calendar2Style.surface : Color.clear,
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
                        ZStack {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(cat.color)
                                .frame(width: 30, height: 30)

                            ColorPicker(
                                L10n.tr("calendar.management.category.select_color"),
                                selection: Binding(
                                    get: { cat.color },
                                    set: { cat.hexColor = Self.hexString(from: $0) }
                                ),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .opacity(0.02)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(L10n.tr(
                            "calendar.management.category.change_color",
                            cat.name.isEmpty ? L10n.tr("calendar.management.category.unnamed") : cat.name
                        ))

                        TextField(L10n.tr("calendar.management.category.name_placeholder"), text: $cat.name)
                            .font(.system(size: 16))
                            .foregroundStyle(Calendar2Style.text)

                        loadKindMenu(selection: $cat.loadKind, inherited: nil, allowsInheritance: false)

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
                                .foregroundStyle(Calendar2Style.faint)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(HapticButtonStyle())
                    }
                    .padding(.vertical, 14)

                }
                .padding(.horizontal, 20)
                Divider().padding(.leading, 20)
            }

            Button {
                let id = "new_cat_\(nextId)"
                let colorIdx = nextId % paletteHex.count
                nextId += 1
                withAnimation {
                    cats.append(EditableCat(id: id, name: "", hexColor: paletteHex[colorIdx], loadKind: nil))
                    expandedId = id
                }
            } label: {
                addRowLabel(L10n.tr("calendar.management.category.add"))
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
                                Text(cat.name.isEmpty ? L10n.tr("calendar.management.category.no_name") : cat.name)
                                    .font(.system(size: 14, weight: isOn ? .semibold : .medium))
                                    .foregroundStyle(isOn ? Calendar2Style.text : Calendar2Style.text2)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                isOn ? cat.color.opacity(0.18) : Calendar2Style.surface2,
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
                    Text(L10n.tr("calendar.management.subcategory.empty"))
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

            let addCatName = selCat?.name.isEmpty == false ? selCat!.name : L10n.tr("calendar.management.category.uncategorized")
            Button {
                let id = "new_sub_\(nextId)"
                nextId += 1
                withAnimation {
                    subs.append(EditableSub(id: id, name: "", catId: selectedSubCatId ?? cats.first?.id ?? "", tracksFocus: false, loadKindOverride: nil))
                    expandedId = id
                }
            } label: {
                addRowLabel(L10n.tr("calendar.management.subcategory.add_for_category", addCatName))
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

                TextField(L10n.tr("calendar.management.subcategory.name_placeholder"), text: $subs[idx].name)
                    .font(.system(size: 16))
                    .foregroundStyle(Calendar2Style.text)

                let inheritedKind = cats.first(where: { $0.id == subs[idx].catId })?.loadKind
                loadKindMenu(selection: $subs[idx].loadKindOverride, inherited: inheritedKind, allowsInheritance: true)

                Button {
                    subs[idx].tracksFocus.toggle()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "scope")
                            .font(.system(size: 12, weight: .medium))
                        Text(L10n.tr("calendar.management.subcategory.focus"))
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(subs[idx].tracksFocus ? Calendar2Style.accent : Calendar2Style.faint)
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
                        .foregroundStyle(Calendar2Style.faint)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(HapticButtonStyle())
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    private static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil) else {
            return "8A8F9C"
        }
        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    private func loadKindMenu(selection: Binding<LoadKind?>, inherited: LoadKind?, allowsInheritance: Bool) -> some View {
        Menu {
            if allowsInheritance {
                Button(L10n.tr("calendar.management.load_kind.inherit", inherited?.label ?? L10n.tr("calendar.management.load_kind.unset"))) {
                    selection.wrappedValue = nil
                }
                Divider()
            }
            ForEach(LoadKind.allCases) { kind in
                Button(kind.label) {
                    selection.wrappedValue = kind
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 12, weight: .medium))
                Text(selection.wrappedValue?.label ?? inherited?.label ?? L10n.tr("calendar.management.load_kind.default"))
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .foregroundStyle(selection.wrappedValue == nil && inherited == nil ? Calendar2Style.faint : Calendar2Style.accent)
            .frame(width: 48, height: 34)
        }
        .buttonStyle(HapticButtonStyle())
    }

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
            return orig.name != cat.name || orig.hexColor != cat.hexColor || orig.loadKind != cat.loadKind
        }
        let modifiedSubs = subs.filter { sub in
            guard origSubIds.contains(sub.id),
                  let orig = originalSubs.first(where: { $0.id == sub.id }) else { return false }
            return orig.name != sub.name || orig.tracksFocus != sub.tracksFocus || orig.loadKindOverride != sub.loadKindOverride
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
                let created = try await store.createCategory(name: cat.name, hexColor: "#\(cat.hexColor)", loadKind: cat.loadKind)
                idMap[cat.id] = created.id
            }

            // 4. Update modified categories
            for cat in modifiedCats {
                try await store.updateCategory(id: cat.id, name: cat.name, hexColor: "#\(cat.hexColor)", loadKind: cat.loadKind)
            }

            // 5. Create new types (resolve temp category IDs)
            for sub in newSubs {
                let realCatId = idMap[sub.catId] ?? sub.catId
                _ = try await store.createType(categoryId: realCatId, name: sub.name, tracksFocus: sub.tracksFocus, loadKindOverride: sub.loadKindOverride)
            }

            // 6. Update modified types
            for sub in modifiedSubs {
                try await store.updateType(id: sub.id, name: sub.name, tracksFocus: sub.tracksFocus, loadKindOverride: sub.loadKindOverride)
            }

            // 7. Reload to ensure consistent state
            try await store.reloadCategories()

            // Refresh local state from server data (keep sheet open)
            let freshCats = store.categories.map { EditableCat(from: $0) }
            let freshSubs = store.categories.flatMap { cat in
                cat.types.map { EditableSub(id: $0.id, name: $0.label, catId: cat.id, tracksFocus: $0.tracksFocus, loadKindOverride: $0.loadKindOverride) }
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
    var loadKind: LoadKind?

    var color: Color { Color(hex: hexColor) }

    init(id: String, name: String, hexColor: String, loadKind: LoadKind?) {
        self.id = id
        self.name = name
        self.hexColor = hexColor
        self.loadKind = loadKind
    }

    init(from category: Calendar2Category) {
        id = category.id
        name = category.label
        loadKind = category.loadKind
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
    var loadKindOverride: LoadKind?
}
