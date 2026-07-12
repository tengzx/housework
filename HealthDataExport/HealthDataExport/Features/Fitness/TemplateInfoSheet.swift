import SwiftUI

// MARK: - Template Info Sheet (新建 & 修改 复用)

struct TemplateInfoSheet: View {
    let title: String
    let confirmLabel: String
    let initialName: String
    let initialTheme: String
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var trainingTheme: String
    @FocusState private var nameFocused: Bool

    init(title: String, confirmLabel: String, initialName: String, initialTheme: String,
         onSave: @escaping (String, String?) -> Void) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.initialName = initialName
        self.initialTheme = initialTheme
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _trainingTheme = State(initialValue: initialTheme)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.tr("fitness.template.info.name_placeholder"), text: $name)
                        .focused($nameFocused)
                    TextField(L10n.tr("fitness.template.info.theme_placeholder"), text: $trainingTheme)
                } footer: {
                    if title == L10n.tr("fitness.template.info.new_title") {
                        Text(L10n.tr("fitness.template.info.new_footer"))
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.cancel")) { Haptics.tap(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.tap()
                        save()
                    } label: {
                        Text(confirmLabel).fontWeight(.semibold)
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let trimName = name.trimmingCharacters(in: .whitespaces)
        guard !trimName.isEmpty else { return }
        let theme: String? = trainingTheme.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : trainingTheme.trimmingCharacters(in: .whitespaces)
        onSave(trimName, theme)
        dismiss()
    }
}
