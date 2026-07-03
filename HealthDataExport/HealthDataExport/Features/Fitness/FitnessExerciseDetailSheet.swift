import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class ExerciseDetailViewModel: ObservableObject {
    @Published private(set) var detail: FitnessExerciseDetail?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func load(id: Int) async {
        guard detail == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await FitnessAPIClient.exerciseDetail(id: id)
        } catch {
            errorMessage = "加载失败，请检查网络"
        }
    }
}

// MARK: - Sheet

struct FitnessExerciseDetailSheet: View {
    let exercise: FitnessExercise

    @StateObject private var vm = ExerciseDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "E7E7EB"), in: Circle())
                }
                Spacer()
                Text("动作详情")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                // Balance the leading button
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            if vm.isLoading && vm.detail == nil {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mediaCard
                        headerCard
                        muscleSection
                        guidanceSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(hex: "F4F4F6").ignoresSafeArea())
        .task { await vm.load(id: exercise.id) }
    }

    // MARK: Media (GIF / image)

    private var animationUrl: String? {
        let s = vm.detail?.animationUrl?.trimmingCharacters(in: .whitespaces)
        return (s?.isEmpty == false) ? s : nil
    }
    private var imageUrl: String? {
        let s = vm.detail?.imageUrl?.trimmingCharacters(in: .whitespaces)
        return (s?.isEmpty == false) ? s : nil
    }

    @ViewBuilder
    private var mediaCard: some View {
        if let animationUrl {
            mediaContainer { AnimatedGIFView(urlString: animationUrl) }
        } else if let imageUrl, let url = FitnessAPIClient.mediaURL(imageUrl) {
            mediaContainer {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .empty: ProgressView()
                    default: BarbellIcon()
                    }
                }
            }
        }
    }

    private func mediaContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 16) {
            ExerciseThumbnail(urlString: vm.detail?.imageUrl, size: 64, cornerRadius: 16)

            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                HStack(spacing: 6) {
                    Text(category)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "9A9AA0"))
                    if !isSystem {
                        Text("自定义")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "6E5BF0"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "EEEBff"), in: Capsule())
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: Muscles

    @ViewBuilder
    private var muscleSection: some View {
        let primary = vm.detail?.primaryMuscles ?? []
        let secondary = vm.detail?.secondaryMuscles ?? []
        if !primary.isEmpty || !secondary.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !primary.isEmpty {
                    muscleRow(title: "主要肌群", muscles: primary, color: Color(hex: "C4451E"))
                }
                if !secondary.isEmpty {
                    muscleRow(title: "次要肌群", muscles: secondary, color: Color(hex: "9A9AA0"))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func muscleRow(title: String, muscles: [ExerciseMuscle], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "9A9AA0"))
            FlowChips(items: muscles.map { $0.name }, color: color)
        }
    }

    // MARK: Guidance (动作指导)

    @ViewBuilder
    private var guidanceSection: some View {
        if let detail = vm.detail, detail.hasGuidance {
            VStack(alignment: .leading, spacing: 16) {
                guidanceBlock(title: "动作指导", text: detail.instructions)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if vm.detail != nil {
            HStack(spacing: 8) {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(Color(hex: "BFBFC5"))
                Text("暂无动作指导")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "9A9AA0"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func guidanceBlock(title: String, text: String?) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "5B5B61"))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Helpers

    private var category: String {
        vm.detail?.category?.name ?? exercise.category?.name ?? (isSystem ? "系统" : "自定义")
    }
    private var isSystem: Bool { vm.detail?.isSystem ?? exercise.isSystem }
}

// MARK: - Simple wrapping chips

private struct FlowChips: View {
    let items: [String]
    var color: Color

    var body: some View {
        FlexibleWrap(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
    }
}

// A minimal flow layout that wraps its children onto multiple lines.
private struct FlexibleWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var lineWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let added = rows[rows.count - 1].isEmpty ? size.width : lineWidth + spacing + size.width
            if added > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([size])
                lineWidth = size.width
            } else {
                rows[rows.count - 1].append(size)
                lineWidth = added
            }
        }
        let width = rows.map { row in row.reduce(0) { $0 + $1.width } + CGFloat(max(0, row.count - 1)) * spacing }.max() ?? 0
        let height = rows.reduce(0) { acc, row in acc + (row.map { $0.height }.max() ?? 0) } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
