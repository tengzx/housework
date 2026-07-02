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
                    TextField("模板名称（必填）", text: $name)
                        .focused($nameFocused)
                    TextField("训练主题，如：下半身、推胸", text: $trainingTheme)
                } footer: {
                    if title == "新建模板" {
                        Text("保存后可在模板详情中添加锻炼动作。")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { Haptics.tap(); dismiss() }
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
