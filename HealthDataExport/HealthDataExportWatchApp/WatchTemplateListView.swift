import SwiftUI

/// Lists the user's workout templates. Tapping one opens its detail, where the
/// session can be started.
struct WatchTemplateListView: View {
    @ObservedObject private var store = WatchTemplateStore.shared

    private var templates: [FitnessTemplateSummary] { store.templates }
    private var isLoading: Bool { store.isLoading }
    private var errorMessage: String? { store.errorMessage }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if isLoading && templates.isEmpty {
                    ProgressView()
                        .padding(.top, 20)
                } else if let errorMessage, templates.isEmpty {
                    VStack(spacing: 8) {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(WK.muted)
                            .multilineTextAlignment(.center)
                        Button(SharedL10n.tr("common.retry")) { Task { await store.load() } }
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.top, 16)
                } else if templates.isEmpty {
                    Text(SharedL10n.tr("watch.fitness.empty_templates"))
                        .font(.system(size: 13))
                        .foregroundStyle(WK.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                } else {
                    ForEach(templates) { template in
                        NavigationLink {
                            WatchTemplateDetailView(templateId: template.id, name: template.name)
                        } label: {
                            TemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .background(WK.bg.ignoresSafeArea())
        .navigationTitle(SharedL10n.tr("watch.fitness.templates_title"))
        .task { await store.load() }
    }
}

private struct TemplateRow: View {
    let template: FitnessTemplateSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            HStack(spacing: 8) {
                Label("\(template.exerciseCount)", systemImage: "dumbbell.fill")
                Label(SharedL10n.tr("watch.fitness.set_count", template.setCount), systemImage: "list.number")
            }
            .font(.system(size: 11))
            .foregroundStyle(WK.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WK.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
